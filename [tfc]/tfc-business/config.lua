-- Businesses: admins turn a shop location into a business, set its owner and can list it for
-- sale. Each business is its own job (Owner, Manager, Shift Lead, Cashier) with government
-- paychecks, hiring and firing in the Boss Menu, and a savings account only the owner can use.

BusinessConfig = {
    -- Shop types (tfc-shops/config.lua) that can become businesses.
    OwnableTypes = { general = true, ammunation = true, pawn = true },

    -- Ranks every new business starts with (the highest is the Owner, set by admins).
    Ranks = {
        [0] = { label = 'Cashier', pay = 150 },
        [1] = { label = 'Shift Lead', pay = 200 },
        [2] = { label = 'Manager', pay = 250, boss = true },
        [3] = { label = 'Owner', pay = 300, boss = true },
    },
    PayRange = { min = 100, max = 600 },  -- the owner sets pay within this

    -- Sales: employees on duty within WorkDistance of the store share in each sale.
    --   1 or 2 working: each gets `share` (25%); more than 2: they split `pool` (50%) evenly.
    --   The rest goes into the store savings. The buyer never counts as working their own sale.
    WorkDistance = 50.0,
    Split = { share = 0.25, pool = 0.50 },

    -- Stock: owned stores only sell what's on their shelves.
    ShelfMax = 100,          -- most of one item on the shelf
    StartingStock = 10,      -- of every item when a store gets its first owner
    WholesaleRate = 0.5,     -- restock cost = base price x this (paid from the store savings)
    PriceRange = { min = 0.8, max = 2.0 },  -- owner can set prices from 80% to 200% of the base price

    Command = 'business',        -- owners and managers: manage your store
    AdminCommand = 'businesses', -- admins: create businesses, owners, sales, purchase requests
}
