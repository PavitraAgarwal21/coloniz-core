use core::traits::TryInto;
use core::hash::HashStateTrait;
use core::pedersen::PedersenTrait;
use starknet::{ContractAddress, contract_address_const};
use snforge_std::{
    declare, DeclareResultTrait, ContractClassTrait, start_cheat_caller_address,
    stop_cheat_caller_address, start_cheat_nonce, stop_cheat_nonce, start_cheat_block_timestamp,
    stop_cheat_block_timestamp, spy_events, EventSpyAssertionsTrait
};
use karst::interfaces::IJolt::{IJoltDispatcher, IJoltDispatcherTrait};
use karst::interfaces::IERC20::{IERC20Dispatcher, IERC20DispatcherTrait};
use karst::jolt::jolt::Jolt::{Event as JoltEvent, Jolted};
use karst::jolt::jolt::Jolt::{Event as JoltRequestEvent, JoltRequested};
use karst::jolt::jolt::Jolt::{Event as JoltRequestFulfillEvent, JoltRequestFullfilled};
use karst::base::{constants::types::{JoltParams, JoltType, JoltStatus}};

const ADMIN: felt252 = 5382942;
const ADDRESS1: felt252 = 254290;
const ADDRESS2: felt252 = 525616;

// *************************************************************************
//                              SETUP
// *************************************************************************
fn __setup__() -> (ContractAddress, ContractAddress) {
    // deploy jolt contract
    let jolt_contract = declare("Jolt").unwrap().contract_class();
    let (jolt_contract_address, _) = jolt_contract.deploy(@array![ADMIN]).unwrap();

    // deploy mock USDT
    let usdt_contract = declare("USDT").unwrap().contract_class();
    let (usdt_contract_address, _) = usdt_contract
        .deploy(@array![1000000000000000000000, 0, ADDRESS1])
        .unwrap();

    return (jolt_contract_address, usdt_contract_address);
}

// *************************************************************************
//                              TEST - TIP
// *************************************************************************
#[test]
fn test_jolt_tipping() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Tip,
        recipient: ADDRESS2.try_into().unwrap(),
        memo: "hey first tip ever!",
        amount: 2000000000000000000,
        expiration_stamp: 0,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    // approve contract to spend amount
    erc20_dispatcher.approve(jolt_contract_address, 2000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 36000);
    start_cheat_nonce(jolt_contract_address, 23);

    let jolt_id = dispatcher.jolt(jolt_params);

    // calculate expected jolt ID
    let jolt_hash = PedersenTrait::new(0)
        .update(ADDRESS2)
        .update(2000000000000000000)
        .update(0)
        .update(23)
        .update(4)
        .finalize();
    let expected_jolt_id: u256 = jolt_hash.try_into().unwrap();

    // check jolt data
    let jolt_data = dispatcher.get_jolt(jolt_id);
    assert(jolt_data.jolt_id == expected_jolt_id, 'invalid jolt ID');
    assert(jolt_data.jolt_type == JoltType::Tip, 'invalid jolt type');
    assert(jolt_data.sender == ADDRESS1.try_into().unwrap(), 'invalid sender');
    assert(jolt_data.recipient == ADDRESS2.try_into().unwrap(), 'invalid recipient');
    assert(jolt_data.memo == "hey first tip ever!", 'invalid memo');
    assert(jolt_data.amount == 2000000000000000000, 'invalid amount');
    assert(jolt_data.status == JoltStatus::SUCCESSFUL, 'invalid status');
    assert(jolt_data.expiration_stamp == 0, 'invalid expiration stamp');
    assert(jolt_data.block_timestamp == 36000, 'invalid block stamp');
    assert(jolt_data.erc20_contract_address == erc20_contract_address, 'invalid address');

    // check that recipient received his tip
    let balance = erc20_dispatcher.balance_of(ADDRESS2.try_into().unwrap());
    assert(balance == 2000000000000000000, 'incorrect balance');

    stop_cheat_nonce(jolt_contract_address);
    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
fn test_jolting_with_same_params_have_different_jolt_ids() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params_1 = JoltParams {
        jolt_type: JoltType::Tip,
        recipient: ADDRESS2.try_into().unwrap(),
        memo: "hey first tip ever!",
        amount: 2000000000000000000,
        expiration_stamp: 0,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    let jolt_params_2 = JoltParams {
        jolt_type: JoltType::Tip,
        recipient: ADDRESS2.try_into().unwrap(),
        memo: "hey second tip!",
        amount: 2000000000000000000,
        expiration_stamp: 0,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    // approve contract to spend amount
    erc20_dispatcher.approve(jolt_contract_address, 4000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 36000);
    start_cheat_nonce(jolt_contract_address, 23);
    let jolt_id_1 = dispatcher.jolt(jolt_params_1);
    stop_cheat_nonce(jolt_contract_address);

    start_cheat_nonce(jolt_contract_address, 24);
    let jolt_id_2 = dispatcher.jolt(jolt_params_2);
    stop_cheat_nonce(jolt_contract_address);

    // check jolt ids are not equal
    assert(jolt_id_1 != jolt_id_2, 'jolt id should be unique!');

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
#[should_panic(expected: ('Karst: self-tip forbidden!',))]
fn test_tipper_cant_self_tip() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Tip,
        recipient: ADDRESS1.try_into().unwrap(),
        memo: "hey first tip ever!",
        amount: 2000000000000000000,
        expiration_stamp: 0,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    // approve contract to spend amount
    erc20_dispatcher.approve(jolt_contract_address, 2000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());

    dispatcher.jolt(jolt_params);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
#[should_panic(expected: ('Karst: invalid profile address!',))]
fn test_tipper_cant_tip_a_zero_address() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Tip,
        recipient: contract_address_const::<0>(),
        memo: "hey first tip ever!",
        amount: 2000000000000000000,
        expiration_stamp: 0,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    // approve contract to spend amount
    erc20_dispatcher.approve(jolt_contract_address, 2000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());

    dispatcher.jolt(jolt_params);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
fn test_jolt_event_is_emitted_on_tipping() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Tip,
        recipient: ADDRESS2.try_into().unwrap(),
        memo: "hey first tip ever!",
        amount: 2000000000000000000,
        expiration_stamp: 0,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    // approve contract to spend amount
    erc20_dispatcher.approve(jolt_contract_address, 2000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 36000);

    let mut spy = spy_events();
    let jolt_id = dispatcher.jolt(jolt_params);

    // check for events
    let expected_event = JoltEvent::Jolted(
        Jolted {
            jolt_id: jolt_id,
            jolt_type: 'TIP',
            sender: ADDRESS1.try_into().unwrap(),
            recipient: ADDRESS2.try_into().unwrap(),
            block_timestamp: 36000,
        }
    );
    spy.assert_emitted(@array![(jolt_contract_address, expected_event)]);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

// *************************************************************************
//                              TEST - TRANSFER
// *************************************************************************
#[test]
fn test_jolt_transfer() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Transfer,
        recipient: ADDRESS2.try_into().unwrap(),
        memo: "hey first transfer ever!",
        amount: 2000000000000000000,
        expiration_stamp: 0,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    // approve contract to spend amount
    erc20_dispatcher.approve(jolt_contract_address, 2000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 36000);
    start_cheat_nonce(jolt_contract_address, 23);

    let jolt_id = dispatcher.jolt(jolt_params);

    // calculate expected jolt ID
    let jolt_hash = PedersenTrait::new(0)
        .update(ADDRESS2)
        .update(2000000000000000000)
        .update(0)
        .update(23)
        .update(4)
        .finalize();
    let expected_jolt_id: u256 = jolt_hash.try_into().unwrap();

    // check jolt data
    let jolt_data = dispatcher.get_jolt(jolt_id);
    assert(jolt_data.jolt_id == expected_jolt_id, 'invalid jolt ID');
    assert(jolt_data.jolt_type == JoltType::Transfer, 'invalid jolt type');
    assert(jolt_data.sender == ADDRESS1.try_into().unwrap(), 'invalid sender');
    assert(jolt_data.recipient == ADDRESS2.try_into().unwrap(), 'invalid recipient');
    assert(jolt_data.memo == "hey first transfer ever!", 'invalid memo');
    assert(jolt_data.amount == 2000000000000000000, 'invalid amount');
    assert(jolt_data.status == JoltStatus::SUCCESSFUL, 'invalid status');
    assert(jolt_data.expiration_stamp == 0, 'invalid expiration stamp');
    assert(jolt_data.block_timestamp == 36000, 'invalid block stamp');
    assert(jolt_data.erc20_contract_address == erc20_contract_address, 'invalid address');

    // check that recipient received his tip
    let balance = erc20_dispatcher.balance_of(ADDRESS2.try_into().unwrap());
    assert(balance == 2000000000000000000, 'incorrect balance');

    stop_cheat_nonce(jolt_contract_address);
    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
#[should_panic(expected: ('Karst: invalid profile address!',))]
fn test_sender_cant_transfer_to_a_zero_address() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Transfer,
        recipient: contract_address_const::<0>(),
        memo: "hey first transfer ever!",
        amount: 2000000000000000000,
        expiration_stamp: 0,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    // approve contract to spend amount
    erc20_dispatcher.approve(jolt_contract_address, 2000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());

    dispatcher.jolt(jolt_params);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
#[should_panic(expected: ('Karst: self-transfer forbidden!',))]
fn test_sender_cant_self_transfer() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Transfer,
        recipient: ADDRESS1.try_into().unwrap(),
        memo: "hey first transfer ever!",
        amount: 2000000000000000000,
        expiration_stamp: 0,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    // approve contract to spend amount
    erc20_dispatcher.approve(jolt_contract_address, 2000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());

    dispatcher.jolt(jolt_params);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
fn test_jolt_event_is_emitted_on_transfer() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Transfer,
        recipient: ADDRESS2.try_into().unwrap(),
        memo: "hey first transfer ever!",
        amount: 2000000000000000000,
        expiration_stamp: 0,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    // approve contract to spend amount
    erc20_dispatcher.approve(jolt_contract_address, 2000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 36000);

    let mut spy = spy_events();
    let jolt_id = dispatcher.jolt(jolt_params);

    // check for events
    let expected_event = JoltEvent::Jolted(
        Jolted {
            jolt_id: jolt_id,
            jolt_type: 'TRANSFER',
            sender: ADDRESS1.try_into().unwrap(),
            recipient: ADDRESS2.try_into().unwrap(),
            block_timestamp: 36000,
        }
    );
    spy.assert_emitted(@array![(jolt_contract_address, expected_event)]);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

// *************************************************************************
//                              TEST - REQUEST
// *************************************************************************
#[test]
fn test_jolt_request() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Request,
        recipient: ADDRESS1.try_into().unwrap(),
        memo: "hey first request ever!",
        amount: 2000000000000000000,
        expiration_stamp: 15640,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS2.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);
    start_cheat_nonce(jolt_contract_address, 23);

    let jolt_id = dispatcher.jolt(jolt_params);

    // calculate expected jolt ID
    let jolt_hash = PedersenTrait::new(0)
        .update(ADDRESS1)
        .update(2000000000000000000)
        .update(0)
        .update(23)
        .update(4)
        .finalize();
    let expected_jolt_id: u256 = jolt_hash.try_into().unwrap();

    // check jolt data
    let jolt_data = dispatcher.get_jolt(jolt_id);
    assert(jolt_data.jolt_id == expected_jolt_id, 'invalid jolt ID');
    assert(jolt_data.jolt_type == JoltType::Request, 'invalid jolt type');
    assert(jolt_data.sender == ADDRESS2.try_into().unwrap(), 'invalid sender');
    assert(jolt_data.recipient == ADDRESS1.try_into().unwrap(), 'invalid recipient');
    assert(jolt_data.memo == "hey first request ever!", 'invalid memo');
    assert(jolt_data.amount == 2000000000000000000, 'invalid amount');
    assert(jolt_data.status == JoltStatus::PENDING, 'invalid status');
    assert(jolt_data.expiration_stamp == 15640, 'invalid expiration stamp');
    assert(jolt_data.block_timestamp == 5640, 'invalid block stamp');
    assert(jolt_data.erc20_contract_address == erc20_contract_address, 'invalid address');

    stop_cheat_nonce(jolt_contract_address);
    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
#[should_panic(expected: ('Karst: invalid profile address!',))]
fn test_requester_cant_request_to_a_zero_address() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Request,
        recipient: contract_address_const::<0>(),
        memo: "hey first request ever!",
        amount: 2000000000000000000,
        expiration_stamp: 15460,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    dispatcher.jolt(jolt_params);
    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
#[should_panic(expected: ('Karst: self-request forbidden!',))]
fn test_requester_cant_self_request() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Request,
        recipient: ADDRESS1.try_into().unwrap(),
        memo: "hey first request ever!",
        amount: 2000000000000000000,
        expiration_stamp: 15460,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    dispatcher.jolt(jolt_params);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
fn test_jolt_event_is_emitted_on_request() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Request,
        recipient: ADDRESS2.try_into().unwrap(),
        memo: "hey first request ever!",
        amount: 2000000000000000000,
        expiration_stamp: 154600,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 36000);

    let mut spy = spy_events();
    let jolt_id = dispatcher.jolt(jolt_params);

    // check for events
    let expected_event = JoltRequestEvent::JoltRequested(
        JoltRequested {
            jolt_id: jolt_id,
            jolt_type: 'REQUEST',
            sender: ADDRESS1.try_into().unwrap(),
            recipient: ADDRESS2.try_into().unwrap(),
            expiration_timestamp: 154600,
            block_timestamp: 36000,
        }
    );
    spy.assert_emitted(@array![(jolt_contract_address, expected_event)]);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
#[should_panic(expected: ('Karst: invalid expiration stamp',))]
fn test_request_expiration_time_must_be_greater_than_current_time() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Request,
        recipient: ADDRESS2.try_into().unwrap(),
        memo: "hey first request ever!",
        amount: 2000000000000000000,
        expiration_stamp: 460,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    dispatcher.jolt(jolt_params);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
#[should_panic(expected: ('Karst: invalid jolt!',))]
fn test_cant_fulfill_request_if_jolt_type_is_not_a_request() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Transfer,
        recipient: ADDRESS2.try_into().unwrap(),
        memo: "hey first request ever!",
        amount: 2000000000000000000,
        expiration_stamp: 12460,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    // approve contract to spend amount
    erc20_dispatcher.approve(jolt_contract_address, 2000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    let jolt_id = dispatcher.jolt(jolt_params);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);

    // try to fulfill request
    start_cheat_caller_address(jolt_contract_address, ADDRESS2.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    dispatcher.fulfill_request(jolt_id);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
#[should_panic(expected: ('Karst: invalid jolt!',))]
fn test_cant_fulfill_request_if_jolt_status_is_not_pending() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Request,
        recipient: ADDRESS1.try_into().unwrap(),
        memo: "hey first request ever!",
        amount: 2000000000000000000,
        expiration_stamp: 12460,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS2.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    let jolt_id = dispatcher.jolt(jolt_params);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);

    // approve contract to spend amount
    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    erc20_dispatcher.approve(jolt_contract_address, 5000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // try to fulfill request
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    dispatcher.fulfill_request(jolt_id);
    dispatcher.fulfill_request(jolt_id);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
#[should_panic(expected: ('Karst: not request recipient!',))]
fn test_cant_fulfill_request_if_sender_is_not_initial_recipient() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Request,
        recipient: ADDRESS2.try_into().unwrap(),
        memo: "hey first request ever!",
        amount: 2000000000000000000,
        expiration_stamp: 12460,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    let jolt_id = dispatcher.jolt(jolt_params);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);

    // try to fulfill request
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    dispatcher.fulfill_request(jolt_id);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
fn test_if_expiration_time_has_exceeded_jolt_fails_with_expired_status() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Request,
        recipient: ADDRESS2.try_into().unwrap(),
        memo: "hey first request ever!",
        amount: 2000000000000000000,
        expiration_stamp: 8460,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    let jolt_id = dispatcher.jolt(jolt_params);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);

    // try to fulfill request
    start_cheat_caller_address(jolt_contract_address, ADDRESS2.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 95640);

    let status = dispatcher.fulfill_request(jolt_id);

    let jolt_data = dispatcher.get_jolt(jolt_id);
    assert(jolt_data.status == JoltStatus::EXPIRED, 'invalid jolt status');
    assert(status == false, 'invalid return status');

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
fn test_fulfill_request() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Request,
        recipient: ADDRESS1.try_into().unwrap(),
        memo: "hey first request ever!",
        amount: 2000000000000000000,
        expiration_stamp: 8460,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS2.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    let jolt_id = dispatcher.jolt(jolt_params);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);

    // approve contract to spend amount
    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    erc20_dispatcher.approve(jolt_contract_address, 2000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // fulfill request
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5840);

    let status = dispatcher.fulfill_request(jolt_id);

    // check jolt data
    let jolt_data = dispatcher.get_jolt(jolt_id);
    assert(jolt_data.jolt_type == JoltType::Request, 'invalid jolt type');
    assert(jolt_data.sender == ADDRESS2.try_into().unwrap(), 'invalid sender');
    assert(jolt_data.recipient == ADDRESS1.try_into().unwrap(), 'invalid recipient');
    assert(jolt_data.memo == "hey first request ever!", 'invalid memo');
    assert(jolt_data.amount == 2000000000000000000, 'invalid amount');
    assert(jolt_data.status == JoltStatus::SUCCESSFUL, 'invalid status');
    assert(jolt_data.expiration_stamp == 8460, 'invalid expiration stamp');
    assert(jolt_data.block_timestamp == 5640, 'invalid block stamp');
    assert(jolt_data.erc20_contract_address == erc20_contract_address, 'invalid address');
    assert(status == true, 'invalid return status');

    // check that recipient received his tip
    let balance = erc20_dispatcher.balance_of(ADDRESS2.try_into().unwrap());
    assert(balance == 2000000000000000000, 'incorrect balance');

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}

#[test]
fn test_jolt_event_is_emitted_on_request_fulfillment() {
    let (jolt_contract_address, erc20_contract_address) = __setup__();
    let dispatcher = IJoltDispatcher { contract_address: jolt_contract_address };
    let erc20_dispatcher = IERC20Dispatcher { contract_address: erc20_contract_address };

    let jolt_params = JoltParams {
        jolt_type: JoltType::Request,
        recipient: ADDRESS1.try_into().unwrap(),
        memo: "hey first request ever!",
        amount: 2000000000000000000,
        expiration_stamp: 8460,
        auto_renewal: (false, 0),
        erc20_contract_address: erc20_contract_address
    };

    // jolt
    start_cheat_caller_address(jolt_contract_address, ADDRESS2.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5640);

    let jolt_id = dispatcher.jolt(jolt_params);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);

    // approve contract to spend amount
    start_cheat_caller_address(erc20_contract_address, ADDRESS1.try_into().unwrap());
    erc20_dispatcher.approve(jolt_contract_address, 2000000000000000000);
    stop_cheat_caller_address(erc20_contract_address);

    // fulfill request
    start_cheat_caller_address(jolt_contract_address, ADDRESS1.try_into().unwrap());
    start_cheat_block_timestamp(jolt_contract_address, 5840);

    let mut spy = spy_events();
    dispatcher.fulfill_request(jolt_id);

    // check for events
    let expected_event = JoltRequestFulfillEvent::JoltRequestFullfilled(
        JoltRequestFullfilled {
            jolt_id: jolt_id,
            jolt_type: 'REQUEST FULFILLMENT',
            sender: ADDRESS1.try_into().unwrap(),
            recipient: ADDRESS2.try_into().unwrap(),
            expiration_timestamp: 8460,
            block_timestamp: 5840,
        }
    );
    spy.assert_emitted(@array![(jolt_contract_address, expected_event)]);

    stop_cheat_block_timestamp(jolt_contract_address);
    stop_cheat_caller_address(jolt_contract_address);
}