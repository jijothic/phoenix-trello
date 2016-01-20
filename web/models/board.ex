defmodule PhoenixTrello.Board do
  use PhoenixTrello.Web, :model
  use Ecto.Model.Callbacks

  alias __MODULE__
  alias PhoenixTrello.{Repo, Permalink, List, Comment, Card, UserBoard, User}

  @primary_key {:id, Permalink, autogenerate: true}

  schema "boards" do
    field :name, :string
    field :slug, :string

    belongs_to :user, User
    has_many :lists, List
    has_many :cards, through: [:lists, :cards]
    has_many :user_boards, UserBoard
    has_many :invited_users, through: [:user_boards, :user]

    timestamps
  end

  @required_fields ~w(name user_id)
  @optional_fields ~w(slug)

  after_insert Board, :insert_user_board

  @doc """
  Creates a changeset based on the `model` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(model, params \\ :empty) do
    model
    |> cast(params, @required_fields, @optional_fields)
    |> slugify_name()
  end

  def insert_user_board(changeset) do
    board_id = changeset.model.id
    user_id = changeset.model.user_id

    user_board_changeset = UserBoard.changeset(%UserBoard{}, %{"board_id": board_id, "user_id": user_id})

    Repo.insert!(user_board_changeset)

    changeset
  end

  def for_user(query \\ %Board{}, user_id) do
    from board in query,
    left_join: user_boards in assoc(board, :user_boards),
    where: board.user_id == ^user_id or user_boards.user_id == ^user_id,
    limit: 1
  end

  def with_everything(query) do
    comments_query = from c in Comment, order_by: [desc: c.inserted_at], preload: :user
    cards_query = from c in Card, order_by: c.position, preload: [[comments: ^comments_query], :members]
    lists_query = from l in List, order_by: l.position, preload: [cards: ^cards_query]

    from b in query, preload: [:user, :invited_users, lists: ^lists_query]
  end

  def slug_id(board) do
    "#{board.id}-#{board.slug}"
  end

  defp slugify_name(current_changeset) do
    if name = get_change(current_changeset, :name) do
      put_change(current_changeset, :slug, slugify(name))
    else
      current_changeset
    end
  end

  defp slugify(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^\w-]+/, "-")
  end
end

defimpl Phoenix.Param, for: Board do
  def to_param(%{slug: slug, id: id}) do
    "#{id}-#{slug}"
  end
end

defimpl Poison.Encoder, for: PhoenixTrello.Board do
  def encode(model, options) do
    model
    |> Map.take([:name, :lists, :user, :invited_users])
    |> Map.put(:id, PhoenixTrello.Board.slug_id(model))
    |> Poison.Encoder.encode(options)
  end
end
