// Copyright (c) 2022, Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module move_marketplace::marketplace {
    use std::option::{Self, Option};
    use sui::id::{Self, ID, VersionedID};
    use sui::transfer::{Self};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::event;
    use std::vector;


    struct Marketplace has key {
        id: VersionedID,
        listings: vector<ID>,
        offers: vector<ID>,
    }

    /// An object held in escrow
    struct EscrowedObj<T: key + store, phantom C> has key, store {
        id: VersionedID,
        /// owner of the escrowed object
        creator: address,
        /// Amount of Coin<C> the owner wants in exchange.
        exchange_for: u64, 
        /// the escrowed object
        escrowed: Option<T>,
    }

    struct ItemListedEvent has copy, drop{
        escrow_id: ID,
        creator: address,
    }

    // Error codes
    /// An attempt to cancel escrow by a different user than the owner
    const EWrongOwner: u64 = 0;
    // Exchange by a different user than the `recipient` of the escrowed object
    const EWrongRecipient: u64 = 1;
    /// Exchange with a different item than the `exchange_for` field
    const EWrongExchangeObject: u64 = 2;
    /// The escrow has already been exchanged or cancelled
    const EAlreadyExchangedOrCancelled: u64 = 3;
    /// The Coin amount supplied is not exactly the ask.
    const EIncorrectPayment: u64 = 4;

    /// Create an escrow for exchanging goods with counterparty
    public entry fun create_market(ctx: &mut TxContext) {
        let id = tx_context::new_id(ctx);
        let listings = vector::empty();
        let offers = vector::empty();

        let market_place = Marketplace {
            id,
            listings,
            offers
        };
        transfer::share_object(market_place);
    }

    public entry fun create<T: key + store, C>(
        marketplace: &mut Marketplace,
        exchange_for: u64,
        escrowed_item: T,
        ctx: &mut TxContext
    ) {
        let creator = tx_context::sender(ctx);
        let id = tx_context::new_id(ctx);
        let escrowed = option::some(escrowed_item);

        //potentially add this to a Bag of IDs for future querying.
        let escrow = EscrowedObj<T, C> {
            id, creator, exchange_for, escrowed
        };

        event::emit(ItemListedEvent {
            escrow_id: *id::inner(&escrow.id),
            creator: escrow.creator,
        });

        vector::push_back(&mut marketplace.listings, *id::inner(&escrow.id));

        transfer::share_object(
            escrow
        );
    }

    // actually make an exchange - todo add royaltys and other security checks
    public entry fun exchange<T: key + store, C>(
        paid: Coin<C>,
        escrow: &mut EscrowedObj<T, C>,
        ctx: &mut TxContext
    ) {
        assert!(option::is_some(&escrow.escrowed), EAlreadyExchangedOrCancelled);
        let escrowed_item = option::extract<T>(&mut escrow.escrowed);

        assert!(coin::value(&paid) == escrow.exchange_for, EIncorrectPayment);
        // everything matches. do the swap!
        transfer::transfer(paid, escrow.creator);
        transfer::transfer(escrowed_item, tx_context::sender(ctx));
    }

    /// The `creator` can cancel the escrow and get back the escrowed item
    public entry fun cancel<T: key + store, C>(
        marketplace: &mut Marketplace,
        escrow: &mut EscrowedObj<T, C>,
        ctx: &mut TxContext
    ) {
        assert!(&tx_context::sender(ctx) == &escrow.creator, EWrongOwner);
        assert!(option::is_some(&escrow.escrowed), EAlreadyExchangedOrCancelled);

        let (_a, idx) = vector::index_of(&marketplace.listings, id::inner(&escrow.id));
        vector::remove(&mut marketplace.listings, idx);

        transfer::transfer(option::extract<T>(&mut escrow.escrowed), escrow.creator);
    }
}

