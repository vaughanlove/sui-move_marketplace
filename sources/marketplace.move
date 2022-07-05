module move_marketplace::marketplace {
    use sui::id::{Self, ID, VersionedID};
    use sui::transfer::{Self, ChildRef};
    use std::vector::Self;
    use std::option::{Self, Option};

    struct Marketplace<phantom T: key + store> has key, store {
        id: VersionedID,
        listings: vector<ChildRef<T>>,
        totalListings: u64,
        prices: vector<u64>,
    }

    public fun size<T: key + store>(mkp: &Marketplace<T>): u64 {
        vector::length(&mkp.listings)
    }

    public fun fetchPrice()

    /// Look for the object identified by `id_bytes` in the collection.
    /// Returns the index if found, none if not found.
    fun find<T: key + store>(mkp: &Marketplace<T>, child: &T): Option<u64> {
        let i = 0;
        let len = size(mkp);
        while (i < len) {
            let child_ref = vector::borrow(&mkp.listings, i);
            if (transfer::is_child(child_ref,  child)) {
                return option::some(i)
            };
            i = i + 1;
        };
        option::none()
    }
}