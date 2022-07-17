// Copyright (c) 2022, Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

module move_marketplace::marketplace {
    use sui::bag::{Self, Bag};
    use sui::tx_context::{Self, TxContext};
    use sui::id::{ID, VersionedID};
    use sui::typed_id::{Self, TypedID};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use std::option::{Self, Option};
    use std::vector;
    use sui::balance::{Self, Balance};


    // For when amount paid does not match the expected.
    const EAmountIncorrect: u64 = 0;

    // For when someone tries to delist without ownership.
    const ENotOwner: u64 = 1;

    // when someone tries to buy/delist a listing that is not listed.
    const EAlreadyExchangedOrCancelled: u64 = 2;

    struct Marketplace has key {
        id: VersionedID,
        bag_id: TypedID<Bag>,
    }

    /// A single listing which contains the listed item and its price in [`Coin<C>`].
    struct Listing<T: key + store, phantom C> has key, store {
        id: VersionedID,
        item: Option<T>,
        ask: u64, // Coin<C>
        owner: address,
        offers: vector<Offer<C>>,
    }

    struct Offer<phantom C> has store {
        paid: Balance<C>,
        offerer: address,
    }

    /// Create a new shared Marketplace.
    public entry fun create(ctx: &mut TxContext) {
        let id = tx_context::new_id(ctx);
        let bag = bag::new(ctx);
        let bag_id = typed_id::new(&bag);
        bag::transfer_to_object_id(bag, &id);
        let market_place = Marketplace {
            id,
            bag_id,
        };
        transfer::share_object(market_place);
    }

    /// List an item at the Marketplace.
    public entry fun list<T: key + store, C>(
        _marketplace: &Marketplace,
        objects: &mut Bag,
        item: T,
        ask: u64,
        ctx: &mut TxContext
    ) {
        let id = tx_context::new_id(ctx);

        let offers = vector::empty();

        let listing = Listing<T, C> {
            id,
            item: option::some(item),
            ask,
            owner: tx_context::sender(ctx),
            offers,
        };


        bag::add(objects, listing, ctx);
    }

    /// Remove listing and get an item back. Only owner can do that.
    public fun delist<T: key + store, C>(
        _marketplace: &Marketplace,
        objects: &mut Bag,
        listing: bag::Item<Listing<T, C>>,
        ctx: &mut TxContext
    ): T {
        let listing = bag::remove(objects, listing);

        assert!(option::is_some(&listing.item), EAlreadyExchangedOrCancelled);
        let item = option::extract<T>(&mut listing.item);

        assert!(tx_context::sender(ctx) == listing.owner, ENotOwner);
        
        bag::add(objects, listing, ctx);

        item
    }

    /// Call [`delist`] and transfer item to the sender.
    public entry fun delist_and_take<T: key + store, C>(
        _marketplace: &Marketplace,
        objects: &mut Bag,
        listing: bag::Item<Listing<T, C>>,
        ctx: &mut TxContext
    ) {
        let item = delist(_marketplace, objects, listing, ctx);
        transfer::transfer(item, tx_context::sender(ctx));
    }

    /// Purchase an item using a known Listing. Payment is done in Coin<C>.
    /// Amount paid must match the requested amount. If conditions are met,
    /// owner of the item gets the payment and buyer receives their item.
    public fun buy<T: key + store, C>(
        objects: &mut Bag,
        listing: bag::Item<Listing<T, C>>,
        paid: Coin<C>,
        ctx: &mut TxContext,
    ): T {
        let listing = bag::remove(objects, listing);

        assert!(option::is_some(&listing.item), EAlreadyExchangedOrCancelled);
        let item = option::extract<T>(&mut listing.item);


        assert!(listing.ask == coin::value(&paid), EAmountIncorrect);

        transfer::transfer(paid, listing.owner);
        
        bag::add(objects, listing, ctx);

        item
    }

    public entry fun make_offer<T: key + store, C>(
        _marketplace: &Marketplace,
        listing: bag::Item<Listing<T, C>>,
        objects: &mut Bag,
        paid: Coin<C>,
        ctx: &mut TxContext,
    ) {
        let listing = bag::remove(objects, listing);

        let offer = Offer<C> {
            paid: coin::into_balance(paid),
            offerer: tx_context::sender(ctx),
        };

        vector::push_back(&mut listing.offers, offer);
        
        bag::add(objects, listing, ctx);
    }

    public entry fun accept_offer<T: key + store, C>(
        _marketplace: &Marketplace,
        listing: bag::Item<Listing<T, C>>,
        objects: &mut Bag,
        from: address,
        ctx: &mut TxContext,
    ){
        let listing = bag::remove(objects, listing);

        // need to check that person calling is the owner of the item..
        assert!(tx_context::sender(ctx) == listing.owner, ENotOwner);

        assert!(option::is_some(&listing.item), EAlreadyExchangedOrCancelled);

        let index = 0;
        while (index < vector::length(&listing.offers)) {
            let claimed_id = vector::borrow_mut(&mut listing.offers, index);
            if (claimed_id.offerer == from) {
                let item = option::extract<T>(&mut listing.item);
                transfer::transfer(item, from);
                let amount = balance::value(&mut claimed_id.paid);
                let payment = coin::take(&mut claimed_id.paid, amount, ctx);
                transfer::transfer(payment, listing.owner);
            };
            index = index + 1;
        };
        bag::add(objects, listing, ctx);

    }

    /// Call [`buy`] and transfer item to the sender.
    public entry fun buy_and_take<T: key + store, C>(
        _marketplace: &Marketplace,
        listing: bag::Item<Listing<T, C>>,
        objects: &mut Bag,
        paid: Coin<C>,
        ctx: &mut TxContext
    ) {
        transfer::transfer(buy(objects, listing, paid, ctx), tx_context::sender(ctx))
    }

    /// Check whether an object was listed on a Marketplace.
    public fun contains(objects: &Bag, id: &ID): bool {
        bag::contains(objects, id)
    }

    /// Returns the size of the Marketplace.
    public fun size(objects: &Bag): u64 {
        bag::size(objects)
    }
}

#[test_only]
module move_marketplace::marketplaceTests {
    use sui::id::{Self, VersionedID};
    use sui::bag::{Self, Bag};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context;
    use sui::test_scenario::{Self, Scenario};
    use move_marketplace::marketplace::{Self, Marketplace, Listing};

    // Simple Kitty-NFT data structure.
    struct Kitty has key, store {
        id: VersionedID,
        kitty_id: u8
    }

    const ADMIN: address = @0xA55;
    const SELLER: address = @0x00A;
    const BUYER: address = @0x00B;

    /// Create a shared [`Marketplace`].
    fun create_marketplace(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, &ADMIN);
        marketplace::create(test_scenario::ctx(scenario));
    }

    /// Mint SUI and send it to BUYER.
    fun mint_some_coin(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, &ADMIN);
        let coin = coin::mint_for_testing<SUI>(1000, test_scenario::ctx(scenario));
        transfer::transfer(coin, BUYER);
    }

    /// Mint Kitty NFT and send it to SELLER.
    fun mint_kitty(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, &ADMIN);
        let nft = Kitty { id: tx_context::new_id(test_scenario::ctx(scenario)), kitty_id: 1 };
        transfer::transfer(nft, SELLER);
    }

    // SELLER lists Kitty at the Marketplace for 100 SUI.
    fun list_kitty(scenario: &mut Scenario) {
        test_scenario::next_tx(scenario, &SELLER);
        let mkp_wrapper = test_scenario::take_shared<Marketplace>(scenario);
        let mkp = test_scenario::borrow_mut(&mut mkp_wrapper);
        let bag = test_scenario::take_child_object<Marketplace, Bag>(scenario, mkp);
        let nft = test_scenario::take_owned<Kitty>(scenario);

        marketplace::list<Kitty, SUI>(mkp, &mut bag, nft, 100, test_scenario::ctx(scenario));
        test_scenario::return_shared(scenario, mkp_wrapper);
        test_scenario::return_owned(scenario, bag);
    }

    #[test]
    fun list_and_delist() {
        let scenario = &mut test_scenario::begin(&ADMIN);

        create_marketplace(scenario);
        mint_kitty(scenario);
        list_kitty(scenario);

        test_scenario::next_tx(scenario, &SELLER);
        {
            let mkp_wrapper = test_scenario::take_shared<Marketplace>(scenario);
            let mkp = test_scenario::borrow_mut(&mut mkp_wrapper);
            let bag = test_scenario::take_child_object<Marketplace, Bag>(scenario, mkp);
            let listing = test_scenario::take_child_object<Bag, bag::Item<Listing<Kitty, SUI>>>(scenario, &bag);

            // Do the delist operation on a Marketplace.
            let nft = marketplace::delist<Kitty, SUI>(mkp, &mut bag, listing, test_scenario::ctx(scenario));
            let kitty_id = burn_kitty(nft);

            assert!(kitty_id == 1, 0);

            test_scenario::return_shared(scenario, mkp_wrapper);
            test_scenario::return_owned(scenario, bag);
        };
    }

    #[test]
    #[expected_failure(abort_code = 1)]
    fun fail_to_delist() {
        let scenario = &mut test_scenario::begin(&ADMIN);

        create_marketplace(scenario);
        mint_some_coin(scenario);
        mint_kitty(scenario);
        list_kitty(scenario);

        // BUYER attempts to delist Kitty and he has no right to do so. :(
        test_scenario::next_tx(scenario, &BUYER);
        {
            let mkp_wrapper = test_scenario::take_shared<Marketplace>(scenario);
            let mkp = test_scenario::borrow_mut(&mut mkp_wrapper);
            let bag = test_scenario::take_child_object<Marketplace, Bag>(scenario, mkp);
            let listing = test_scenario::take_child_object<Bag, bag::Item<Listing<Kitty, SUI>>>(scenario, &bag);

            // Do the delist operation on a Marketplace.
            let nft = marketplace::delist<Kitty, SUI>(mkp, &mut bag, listing, test_scenario::ctx(scenario));
            let _ = burn_kitty(nft);

            test_scenario::return_shared(scenario, mkp_wrapper);
            test_scenario::return_owned(scenario, bag);
        };
    }

    #[test]
    fun buy_nft() {
        let scenario = &mut test_scenario::begin(&ADMIN);

        create_marketplace(scenario);
        mint_some_coin(scenario);
        mint_kitty(scenario);
        list_kitty(scenario);

        // BUYER takes 100 SUI from his wallet and purchases Kitty.
        test_scenario::next_tx(scenario, &BUYER);
        {
            let coin = test_scenario::take_owned<Coin<SUI>>(scenario);
            let mkp_wrapper = test_scenario::take_shared<Marketplace>(scenario);
            let mkp = test_scenario::borrow_mut(&mut mkp_wrapper);
            let bag = test_scenario::take_child_object<Marketplace, Bag>(scenario, mkp);
            let listing = test_scenario::take_child_object<Bag, bag::Item<Listing<Kitty, SUI>>>(scenario, &bag);
            let payment = coin::take(coin::balance_mut(&mut coin), 100, test_scenario::ctx(scenario));

            // Do the buy call and expect successful purchase.
            let nft = marketplace::buy<Kitty, SUI>(&mut bag, listing, payment, test_scenario::ctx(scenario));
            let kitty_id = burn_kitty(nft);

            assert!(kitty_id == 1, 0);

            test_scenario::return_shared(scenario, mkp_wrapper);
            test_scenario::return_owned(scenario, bag);
            test_scenario::return_owned(scenario, coin);
        };
    }

    #[test]
    #[expected_failure(abort_code = 0)]
    fun fail_to_buy() {
        let scenario = &mut test_scenario::begin(&ADMIN);

        create_marketplace(scenario);
        mint_some_coin(scenario);
        mint_kitty(scenario);
        list_kitty(scenario);

        // BUYER takes 100 SUI from his wallet and purchases Kitty.
        test_scenario::next_tx(scenario, &BUYER);
        {
            let coin = test_scenario::take_owned<Coin<SUI>>(scenario);
            let mkp_wrapper = test_scenario::take_shared<Marketplace>(scenario);
            let mkp = test_scenario::borrow_mut(&mut mkp_wrapper);
            let bag = test_scenario::take_child_object<Marketplace, Bag>(scenario, mkp);
            let listing = test_scenario::take_child_object<Bag, bag::Item<Listing<Kitty, SUI>>>(scenario, &bag);

            // AMOUNT here is 10 while expected is 100.
            let payment = coin::take(coin::balance_mut(&mut coin), 10, test_scenario::ctx(scenario));

            // Attempt to buy and expect failure purchase.
            let nft = marketplace::buy<Kitty, SUI>(&mut bag, listing, payment, test_scenario::ctx(scenario));
            let _ = burn_kitty(nft);

            test_scenario::return_shared(scenario, mkp_wrapper);
            test_scenario::return_owned(scenario, bag);
            test_scenario::return_owned(scenario, coin);
        };
    }

    #[test]
    fun successful_offer_made() {
        let scenario = &mut test_scenario::begin(&ADMIN);

        create_marketplace(scenario);
        mint_some_coin(scenario);
        mint_kitty(scenario);
        list_kitty(scenario);

        // BUYER takes 100 SUI from his wallet and purchases Kitty.
        test_scenario::next_tx(scenario, &BUYER);
        {
            let coin = test_scenario::take_owned<Coin<SUI>>(scenario);
            let mkp_wrapper = test_scenario::take_shared<Marketplace>(scenario);
            let mkp = test_scenario::borrow_mut(&mut mkp_wrapper);
            let bag = test_scenario::take_child_object<Marketplace, Bag>(scenario, mkp);
            let listing = test_scenario::take_child_object<Bag, bag::Item<Listing<Kitty, SUI>>>(scenario, &bag);

            // AMOUNT here is 10 while expected is 100.
            let payment = coin::take(coin::balance_mut(&mut coin), 10, test_scenario::ctx(scenario));

            // Attempt to make a offer for the listing.
            marketplace::make_offer<Kitty, SUI>(mkp, listing, &mut bag, payment, test_scenario::ctx(scenario));

            test_scenario::return_shared(scenario, mkp_wrapper);
            test_scenario::return_owned(scenario, bag);
            test_scenario::return_owned(scenario, coin);
        };
    }

    fun burn_kitty(kitty: Kitty): u8 {
        let Kitty{ id, kitty_id } = kitty;
        id::delete(id);
        kitty_id
    }


}