// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract VoteChainDGT_Config {
    // กำหนดขอบเขตของ Candidate ID และ Party Number (เปลี่ยนได้ในอนาคต)
    uint8 public constant MAX_CANDIDATE_ID = 10;
    uint8 public constant MAX_PARTY_NUMBER = 10;

    // กำหนดสาขาที่รับได้ (เปลี่ยนได้ในอนาคต)
    string public constant BRANCH_DT = "DT";
    string public constant BRANCH_DC = "DC";
}
