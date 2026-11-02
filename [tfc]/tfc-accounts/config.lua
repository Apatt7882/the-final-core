AccountsConfig = {
    ---Every character gets these accounts. Balances are whole dollars.
    ---  default  starting balance for new characters
    ---  min      lowest the balance may go (negative = a credit line)
    ---  max      highest the balance may go (omit for no limit)
    Accounts = {
        cash   = { label = 'Cash',   default = 500,  min = 0 },
        bank   = { label = 'Bank',   default = 5000, min = 0 },
        credit = { label = 'Credit', default = 0,    min = -2500, max = 0 },
    },

    ---Cash is a physical item in tfc-inventory (can be dropped, given, stolen, stored).
    ---The cash balance, HUD and money commands keep working. Needs tfc-inventory running;
    ---if it isn't, cash falls back to a normal account.
    CashItem = true,

    ---Order Charge() tries accounts in when paying for something.
    ChargeOrder = { 'cash', 'bank', 'credit' },

    ---Write every change to tfc_transactions (amount, balance after, reason).
    LogTransactions = true,

    ---Show a notification to the player when a balance changes.
    NotifyChanges = true,

    ---Largest single amount accepted by any function.
    MaxAmount = 1000000000,
}
