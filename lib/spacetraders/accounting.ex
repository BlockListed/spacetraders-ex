defmodule Spacetraders.Accounting do
  use Agent

  def start_link(opts) do
    Agent.start_link(fn -> {%{}, []} end, opts)
  end

  defmodule Account do
    @enforce_keys [:id]
    defstruct [:id, debits: 0, credits: 0, flags: []]

    @type id :: reference() | atom()

    @type option ::
            :debits_must_not_exceed_credits
            | :credits_must_not_exceed_debits

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
      debits_no_exceed = :debits_must_not_exceed_credits in account.flags
      credits_no_exceed = :credits_must_not_exceed_debits in account.flags

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

    {accounts, transactions}
  end

  @spec transact(Agent.agent(), Account.id(), Account.id(), non_neg_integer()) ::
          :ok | {:error, String.t()}
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

        {:ok, {accounts, transactions}}
      else
        _ -> {{:error, "An account went negative!"}, state}
      end
    else
      _ -> {{:error, "One of the accounts doesn't exist!"}, state}
    end
  end
end
