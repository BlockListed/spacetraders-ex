defmodule Spacetraders.Accounting do
  alias Spacetraders.Accounting
  use Agent

  def initial_state() do
    state = {%{}, []}

    {_, state} = upd_create_account(state, :initial_funds, [:credit_balance])
    {_, state} = upd_create_account(state, :funds, [:debit_balance])

    {:ok, agent} = Spacetraders.API.agent()

    {_, state} = upd_transact(state, :funds, :initial_funds, agent["credits"])
    
    # Trading accounts
    {_, state} = upd_create_account(state, :trading_cogs, [:debit_balance])
    {_, state} = upd_create_account(state, :trading_sales_income, [:credit_balance])
    {_, state} = upd_create_account(state, :trading_operating_expenses, [:debit_balance])

    state
  end

  def start_link(opts) do
    Agent.start_link(__MODULE__, :initial_state, [], opts)
  end

  defmodule Account do
    @enforce_keys [:id]
    defstruct [:id, debits: 0, credits: 0, flags: []]

    @type id :: reference() | atom()

    @typedoc """
    `:debit_balance` means credits_must_not_exceed_debits and
    `:credit_balance` means debits_must_not_exceed_credits.
    """
    @type option ::
            :debit_balance
            | :credit_balance

    @type t :: %Account{
            id: id(),
            debits: non_neg_integer(),
            credits: non_neg_integer(),
            flags: [option()]
          }

    @spec debit_account(t(), non_neg_integer()) :: t()
    def debit_account(account, amount) do
      %{account | debits: account.debits + amount}
    end

    @spec credit_account(t(), non_neg_integer()) :: t()
    def credit_account(account, amount) do
      %{account | credits: account.credits + amount}
    end

    @spec check_account_valid(t()) :: :ok | :error
    def check_account_valid(account) do
      debits_no_exceed = :credit_balance in account.flags
      credits_no_exceed = :debit_balance in account.flags

      case {debits_no_exceed, credits_no_exceed} do
        {true, true} ->
          :error

        {true, false} ->
          if debit_account_balance(account) > 0 do
            :ok
          else
            :error
          end

        {false, true} ->
          if credit_account_balance(account) > 0 do
            :ok
          else
            :error
          end

        {false, false} ->
          :ok
      end
    end

    @spec debit_account_balance(t()) :: integer()
    def debit_account_balance(account) do
      account.debits - account.credits
    end

    @spec credit_account_balance(t()) :: integer()
    def credit_account_balance(account) do
      account.credits - account.debits
    end
  end

  defmodule Transaction do
    @enforce_keys [:debit_account, :credit_account, :amount]
    defstruct [:debit_account, :credit_account, :amount]

    @type t :: %Transaction{
            debit_account: Account.id(),
            credit_account: Account.id(),
            amount: non_neg_integer()
          }
  end

  @type state :: {map(), [Transaction.t()]}

  @spec create_account(Agent.agent(), [Account.option()], nil | atom()) :: Account.t()
  def create_account(server, flags \\ [], id \\ nil) do
    id = if(id == nil, do: make_ref(), else: id)

    Agent.get_and_update(server, __MODULE__, :upd_create_account, [flags, id])
  end

  @doc false
  def upd_create_account({accounts, transactions}, flags, id) do
    account = %Account{id: id, flags: flags}

    if Map.has_key?(accounts, id) do
      raise "Duplicate account keys!"
    end

    accounts = Map.put_new(accounts, id, account)

    {account, {accounts, transactions}}
  end

  @spec transact(Agent.agent(), Account.id(), Account.id(), non_neg_integer()) ::
          {:ok, Transaction.t()} | {:error, String.t()}
  def transact(server, debit_account, credit_account, amount) do
    Agent.get_and_update(server, __MODULE__, :upd_transact, [debit_account, credit_account, amount])
  end

  @doc false
  def upd_transact({accounts, transactions} = state, debit_account, credit_account, amount) do
    transaction = %Transaction{
      debit_account: debit_account,
      credit_account: credit_account,
      amount: amount
    }

    with {:ok, debit_account} <- Map.fetch(accounts, debit_account),
         {:ok, credit_account} <- Map.fetch(accounts, credit_account) do
      debit_account = Account.debit_account(debit_account, amount)
      credit_account = Account.credit_account(credit_account, amount)

      with :ok <- Account.check_account_valid(debit_account),
           :ok <- Account.check_account_valid(credit_account) do
        accounts = Map.put(accounts, debit_account.id, debit_account)
        accounts = Map.put(accounts, debit_account.id, debit_account)

        transactions = [transaction | transactions]

        {{:ok, transaction}, {accounts, transactions}}
      else
        _ -> {{:error, "An account went negative!"}, state}
      end
    else
      _ -> {{:error, "One of the accounts doesn't exist!"}, state}
    end
  end

  @spec get_account(Agent.agent(), Account.id()) :: {:some, Account.t()} | :none
  def get_account(server, account) do
    Agent.get(server, __MODULE__, :get_get_account, [account]) 
  end

  @doc false
  def get_get_account({accounts, _}, account) do
    case Map.fetch(accounts, account) do
      {:ok, account} -> {:some, account}
      :error -> :none
    end
  end

  # TODO
  @spec close_account(Agent.agent(), Account.id(), Account.id()) :: {:ok, Transaction.t()} | {:error, String.t()}
  def close_account(server, account, against) do
    Agent.get_and_update(server, __MODULE__, :upd_close_account, [account, against]) 
  end

  @doc false
  def upd_close_account(state, account, against) do
    case get_get_account(state, account) do
      {:some, %Account{}=account} ->
        delta = account.debits - account.credits

        cond do
          delta > 0 ->
            upd_transact(state, against, account.id, delta)
          delta == 0 ->
            # yeah maybe doing a zero transaction is stupid, but we always return a transaction
            upd_transact(state, account.id, against, 0)
          delta < 0 ->
            upd_transact(state, account.id, against, -delta)
        end
      :none -> {{:error, "One of the accounts doesn't exist!"}, state}
    end
  end
end
