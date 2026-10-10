// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {LibDecimalFloatImplementation} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTranscendentalOracle, ORACLE_ONE} from "../../../lib/LibTranscendentalOracle.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {LibTestErrorBound, DOCUMENTED_POW_GUARD, DOCUMENTED_POW10_RAW_ERROR} from "../../../lib/LibTestErrorBound.sol";
import {LibTestExactDecimal} from "../../../lib/LibTestExactDecimal.sol";

contract LibDecimalFloatImplementationPow10Test is Test {
    using LibDecimalFloat for Float;

    function checkPow10(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal pure {
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.pow10(signedCoefficient, exponent);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient, "signedCoefficient");
        assertEq(actualExponent, expectedExponent, "exponent");
    }

    function testExactPows() external pure {
        checkPow10(1e37, -37, 1, 1);
        checkPow10(10e37, -37, 1, 10);
        checkPow10(1, 2, 1, 100);
        checkPow10(2, 0, 1, 2);
        checkPow10(-2, 0, 1, -2);
        checkPow10(0, 0, 1, 0);
        checkPow10(-20, -1, 1, -2);
    }

    /// The result is within half a unit of the true power's 41st digit plus
    /// `DOCUMENTED_POW10_RAW_ERROR` over `DOCUMENTED_POW_GUARD` of that unit,
    /// and the 70 digit reference is within 1e-29 of it, inside 1e-11.
    function testPow10Accuracy() external pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 boundUnits = int256((DOCUMENTED_POW_GUARD / 2 + DOCUMENTED_POW10_RAW_ERROR) * 10 + 1);
        int256[4][] memory references = pow10References();
        for (uint256 i = 0; i < references.length; i++) {
            (int256 signedCoefficient, int256 exponent) =
                LibDecimalFloatImplementation.pow10(references[i][0], references[i][1]);
            int256 unitExponent = references[i][3]
                + LibTestExactDecimal.digits(LibTestExactDecimal.u512(LibTestExactDecimal.abs(references[i][2]))) - 41;
            int256[] memory coefficients = new int256[](2);
            int256[] memory exponents = new int256[](2);
            (coefficients[0], exponents[0]) = (signedCoefficient, exponent);
            (coefficients[1], exponents[1]) = (-references[i][2], references[i][3]);
            int256[] memory boundCoefficients = new int256[](1);
            int256[] memory boundExponents = new int256[](1);
            (boundCoefficients[0], boundExponents[0]) = (boundUnits, unitExponent - 11);
            assertTrue(
                LibTestExactDecimal.absSumLte(coefficients, exponents, boundCoefficients, boundExponents), "pow10 error"
            );
        }
    }

    /// Inputs and their pow10 to 70 significant digits from `bc -l` at scale
    /// 220, as (input coefficient, input exponent, power coefficient, power
    /// exponent).
    function pow10References() internal pure returns (int256[4][] memory references) {
        references = new int256[4][](59);
        references[0] = [int256(2), 0, 1000000000000000000000000000000000000000000000000000000000000000000000, -67];
        references[1] = [int256(-2), 0, 1000000000000000000000000000000000000000000000000000000000000000000000, -71];
        references[2] = [int256(15), -1, 3162277660168379331998893544432718533719555139325216826857504852792594, -68];
        references[3] = [int256(5), -1, 3162277660168379331998893544432718533719555139325216826857504852792594, -69];
        references[4] = [int256(-3), -1, 5011872336272722850015541868849457680604719898328192639296974558890112, -70];
        references[5] =
            [int256(155555), -5, 3593767691533284920715750474230200406773764474930936887702950762584434, -68];
        references[6] =
            [int256(123456789), -5, 3697345199481418293443634460698996744134040798707804633774480048114970, 1165];
        references[7] = [
            int256(99999999999999999999999999999999999999997448),
            -41,
            9999999999999999999999999999999999999412380284267919541438608580764550,
            930
        ];
        references[8] = [int256(1), -60, 1000000000000000000000000000000000000000000000000000000000002302585092, -69];
        references[9] = [int256(-1), -45, 9999999999999999999999999999999999999999999976974149070059543159820085, -70];
        references[10] = [
            int256(30102999566398119521373889472449302676818988146211),
            -50,
            2000000000000000000000000000000000000000000000000006717513730067730770,
            -69
        ];
        references[11] = [
            int256(21474830005), -1, 3162277660168379331998893544432718533719555139325216826857504852792594, 2147482931
        ];
        references[12] = [
            int256(-2147483000250),
            -3,
            5623413251903490803949510397764812314682510430986916640816894237358835,
            -2147483070
        ];
        references[13] = [int256(1), -76, 1000000000000000000000000000000000000000000000000000000000000000000000, -69];
        references[14] = [int256(-1), -76, 9999999999999999999999999999999999999999999999999999999999999999999999, -70];
        references[15] = [
            int256(99999999999999999999999999999999999999999999999999),
            -50,
            9999999999999999999999999999999999999999999999999769741490700595431598,
            -69
        ];
        references[16] = [
            int256(-99999999999999999999999999999999999999999999999999),
            -50,
            1000000000000000000000000000000000000000000000000023025850929940456840,
            -70
        ];
        references[17] = [
            int256(-171327424162538906164302871284713896443485),
            -40,
            7366438776938141470749243455504558785940666350311796601993920263735176,
            -87
        ];
        references[18] = [
            int256(57345151674922187671394257430572207113028),
            -40,
            5426442025437790159188190294572557858505584528530289330160249143642512,
            -64
        ];
        references[19] = [
            int256(286017727512383281507091386145858310669543),
            -40,
            3997355295699168610707480969493266219075655333710476297002661845880510,
            -41
        ];
        references[20] = [
            int256(-285309696650155624657211485138855585773942),
            -40,
            2944627305543738646109213161981333574929274514628450829047314312453362,
            -98
        ];
        references[21] = [
            int256(-56637120812694530821514356423569482217428),
            -40,
            2169141676718827311793983422760424062603000453434976604702429653341150,
            -75
        ];
        references[22] = [
            int256(172035455024766563014182772291716621339086),
            -40,
            1597884936005418772170752224522991144791804972330242358114657902996466,
            -52
        ];
        references[23] = [
            int256(-399291969137772343150120098992997275104399),
            -40,
            1177072155367563751338912320565566539838559724329869526225138733119659,
            -109
        ];
        references[24] = [
            int256(-170619393300311249314422970277711171547884),
            -40,
            8670829968553778353529493892943925639754155864593844028207908244104573,
            -87
        ];
        references[25] = [
            int256(58053182537149844521274158437574932008629),
            -40,
            6387313810859187868406475827900338340433273327087171530192653018815197,
            -64
        ];
        references[26] = [
            int256(286725758374610938356971287152861035565143),
            -40,
            4705175613678565536235464240906490254403032573562191917431014716395593,
            -41
        ];
        references[27] = [
            int256(-284601665787927967807331584131852860878341),
            -40,
            3466038809290550153653204046577856328629330733196660367770795450520199,
            -98
        ];
        references[28] = [
            int256(-55929089950466873971634455416566757321827),
            -40,
            2553236268713041244846551361799393190624550065172746737061595120630661,
            -75
        ];
        references[29] = [
            int256(172743485886994219864062673298719346234687),
            -40,
            1880825865653259947122570920773575396947955920267978543597641254942169,
            -52
        ];
        references[30] = [
            int256(-398583938275544686300240197985994550208798),
            -40,
            1385498858941642138911858432346658220416583412303772138211714650581419,
            -109
        ];
        references[31] = [
            int256(-169911362438083592464543069270708446652284),
            -40,
            1020619251991126091044480315534477008076879860248509832995826005143290,
            -86
        ];
        references[32] = [
            int256(58761213399377501371154059444577656904230),
            -40,
            7518329234357031691113313890246018548264964516782797112559357170614680,
            -64
        ];
        references[33] = [
            int256(287433789236838595206851188159863760460744),
            -40,
            5538331200975528612317470924167591564169196374557318891524424848812241,
            -41
        ];
        references[34] = [
            int256(-283893634925700310957451683124850135982740),
            -40,
            4079777771839252117525249529117489239516232011123571671208895488062067,
            -98
        ];
        references[35] = [
            int256(-55221059088239217121754554409564032426226),
            -40,
            3005343317976695635658145467106609482970890600467833004090239977342655,
            -75
        ];
        references[36] = [
            int256(173451516749221876713942574305722071130287),
            -40,
            2213867755555546579529519953106007305061826187509192027993550735483499,
            -52
        ];
        references[37] = [
            int256(-397875907413317029450360296978991825313197),
            -40,
            1630832128153738889756163068120164919838807768181516964650543116470648,
            -109
        ];
        references[38] = [
            int256(-169203331575855935614663168263705721756683),
            -40,
            1201342502750825469813025609705728783088177609242991166842867807054513,
            -86
        ];
        references[39] = [
            int256(59469244261605158221033960451580381799831),
            -40,
            8849615996647596629243325779186678321506573172655314589462382963411206,
            -64
        ];
        references[40] = [
            int256(288141820099066252056731089166866485356345),
            -40,
            6519015443871693358352593880194320478359492542723959355639105170625749,
            -41
        ];
        references[41] = [
            int256(-283185604063472654107571782117847411087140),
            -40,
            4802192815319505226010103359549189261423774474262851402395143077100803,
            -98
        ];
        references[42] = [
            int256(-54513028226011560271874653402561307530625),
            -40,
            3537505936910334635660075984690196985647127404524187708535268210430548,
            -75
        ];
        references[43] = [
            int256(174159547611449533563822475312724796025888),
            -40,
            2605882090730517971769945785405689837513977256281497967044792867753664,
            -52
        ];
        references[44] = [
            int256(-397167876551089372600480395971989100417596),
            -40,
            1919607088128592381100804359122430141414934212315637669941340820649319,
            -109
        ];
        references[45] = [
            int256(-168495300713628278764783267256702996861082),
            -40,
            1414066809047577520735676504918651820648830705127424116531208244046709,
            -86
        ];
        references[46] = [
            int256(60177275123832815070913861458583106695431),
            -40,
            1041663657534925739359081542999194660846296338805935565136859089975529,
            -63
        ];
        references[47] = [
            int256(288849850961293908906610990173869210251946),
            -40,
            7673351559392489416401059153803329597559622932114881490890189265887950,
            -41
        ];
        references[48] = [
            int256(-282477573201244997257691881110844686191539),
            -40,
            5652527447618759035765084328376905018777594968877169848771655554275839,
            -98
        ];
        references[49] = [
            int256(-53804997363783903421994752395558582635024),
            -40,
            4163899737784600583921981782204223198892567100416735015946832668082026,
            -75
        ];
        references[50] = [
            int256(174867578473677190413702376319727520921489),
            -40,
            3067311249169904110113276312227046326150511096107887719499162282658414,
            -52
        ];
        references[51] = [
            int256(-396459845688861715750600494964986375521996),
            -40,
            2259516052682375133548216537984837155643561510469522999350258701830858,
            -109
        ];
        references[52] = [
            int256(-167787269851400621914903366249700271965481),
            -40,
            1664458666759365270839272923701411494122230278742273973711680145193011,
            -86
        ];
        references[53] = [
            int256(60885305986060471920793762465585831591032),
            -40,
            1226113286542694829389311796328036844388003985152049811882166269941871,
            -63
        ];
        references[54] = [
            int256(289557881823521565756490891180871935147547),
            -40,
            9032088458907173892690483117079053107617981607291358210455831322617602,
            -41
        ];
        references[55] = [
            int256(-281769542339017340407811980103841961295938),
            -40,
            6653432666042926509846648167643321283476725028506728746064989431549557,
            -98
        ];
        references[56] = [
            int256(-53096966501556246572114851388555857739424),
            -40,
            4901210439088553342950526591647952577144864592790904433897627154847901,
            -75
        ];
        // Three units of the 41st digit below 1 and 1e7, where the true
        // power's unit is a tenth of the power of ten's.
        references[57] = [
            int256(-1302883445709755482953386756749815246883),
            -80,
            9999999999999999999999999999999999999999700000000000000000000000000000,
            -70
        ];
        references[58] = [
            int256(6999999999999999999999999999999999999999986971165542902445170466133),
            -66,
            9999999999999999999999999999999999999999700000000000000000000000013067,
            -63
        ];
    }

    function boundFloat(int224 x, int32 exponent) internal pure returns (int224, int32) {
        exponent = int32(bound(exponent, -76, 76));
        Float a = LibDecimalFloat.packLossless(x, exponent);
        vm.assume(a.gt(LibDecimalFloat.packLossless(type(int224).min, 9)));
        vm.assume(a.lt(LibDecimalFloat.packLossless(type(int224).max, 9)));
        return (x, exponent);
    }

    /// Test the current range that we can handle power10 over does not revert.
    function testNoRevert(int224 x, int32 exponent) external pure {
        (x, exponent) = boundFloat(x, exponent);
        LibDecimalFloatImplementation.pow10(x, exponent);
    }

    /// Guard digits of exactly half a unit round up, and one below half
    /// rounds down.
    function testPow10RoundsHalfUp() external pure {
        int256[4] memory xs = [
            int256(10857362048),
            67315644695,
            52839762350034614138096464404871856380432525744962,
            62876337819492131669053461917963730523385842721800
        ];
        int256[4] memory remainders = [int256(5e9), 5e9 - 1, 5e9, 5e9 - 1];
        int256[4] memory carries = [int256(1), 0, 1, 0];
        for (uint256 i = 0; i < xs.length; i++) {
            (int256 unrounded, int256 unroundedExponent) = LibDecimalFloatImplementation.pow10Unrounded(xs[i], -50);
            assertEq(unrounded % 1e10, remainders[i], "remainder");
            checkPow10(xs[i], -50, unrounded / 1e10 + carries[i], unroundedExponent + 10);
        }
    }

    function testPow10One() external pure {
        unchecked {
            int256 exponent = 0;
            for (int256 i = 1; exponent >= -76;) {
                checkPow10(i, exponent, 1, 1);
                exponent--;
                i *= 10;
            }
        }
    }

    function prime(uint256 primeSeed) internal pure returns (uint256) {
        uint256[3] memory primes = [uint256(2), 3, 7];
        return primes[primeSeed % 3];
    }

    /// 10^(j log10(prime) + n) is prime^j 10^n exactly, as prime^j is below
    /// 1e30 and so has fewer than the 41 digits pow10 keeps.
    function testPow10PrimePowersExact(uint256 primeSeed, uint256 j, int256 n) external pure {
        uint256 base = prime(primeSeed);
        j = bound(j, 0, LibTranscendentalOracle.maxPower(base));
        n = bound(n, -1e6, 1e6);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 x = int256(j * LibTranscendentalOracle.log10Prime(base)) + n * int256(ORACLE_ONE);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.pow10(x, -70);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertTrue(LibTestExactDecimal.eq(signedCoefficient, exponent, int256(base ** j), n), "exact");
    }

    /// |pow10(x) - oracle| in billionths of a unit in the result's last place,
    /// for x = j log10(prime) + d + n with |d| up to 1e-3, which spreads the
    /// fraction over [0, 1).
    function pow10OracleError(uint256 primeSeed, uint256 j, int256 d, int256 n) internal pure returns (uint256) {
        uint256 base = prime(primeSeed);
        j = bound(j, 0, LibTranscendentalOracle.maxPower(base));
        d = bound(d, -1e67, 1e67);
        n = bound(n, -1e6, 1e6);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 x = int256(j * LibTranscendentalOracle.log10Prime(base)) + d + n * int256(ORACLE_ONE);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.pow10(x, -70);
        // The true value is base^j 10^d 10^n, and 10^(n - exponent + 9) scales
        // it to billionths of the unit, below 1e51.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 scaled = base ** j * 10 ** uint256(n - exponent + 9);
        uint256 expected = Math.mulDiv(scaled, LibTranscendentalOracle.exp10Small(d), ORACLE_ONE);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 actual = uint256(signedCoefficient) * 1e9;
        return actual > expected ? actual - expected : expected - actual;
    }

    /// Half a unit plus 32.8 billionths, pow10's bound, plus 2 for the
    /// oracle: exp10Small is within a few units of 1e-70, under 1e-18 of
    /// these billionths, and the expected value floors one.
    function testPow10OracleFuzz(uint256 primeSeed, uint256 j, int256 d, int256 n) external pure {
        assertLe(pow10OracleError(primeSeed, j, d, n), 500000034, "pow10 error");
    }

    /// pow10(x + k) is pow10(x) 10^k exactly for an integer k. x is at the
    /// 1e-50 that pow10 truncates its fraction to, so the shift does not move
    /// the truncation.
    function testPow10DecadeShift(int256 x, int256 shift) external pure {
        x = bound(x, -1e55, 1e55);
        shift = bound(shift, -1e5, 1e5);
        (int256 signedCoefficient, int256 exponent) = LibDecimalFloatImplementation.pow10(x, -50);
        (int256 shiftedCoefficient, int256 shiftedExponent) = LibDecimalFloatImplementation.pow10(x + shift * 1e50, -50);
        assertEq(shiftedCoefficient, signedCoefficient, "coefficient");
        assertEq(shiftedExponent, exponent + shift, "exponent");
    }

    /// pow10(k) is exactly 10^k for an integer k however it is written.
    function testPow10IntegersExact(int256 k, uint256 zeros) external pure {
        k = bound(k, -1e30, 1e30);
        zeros = bound(zeros, 0, 40);
        // forge-lint: disable-next-line(unsafe-typecast)
        checkPow10(k * int256(10 ** zeros), -int256(zeros), 1, k);
    }

    /// x < y implies pow10(x) <= pow10(y) + 2E, down to adjacent inputs at
    /// 1e-70.
    function testPow10Monotone(int256 x, int256 gap) external pure {
        x = bound(x, -1e75, 1e75);
        gap = bound(gap, 1, 1e3);
        (int256 lowCoefficient, int256 lowExponent) = LibDecimalFloatImplementation.pow10(x, -70);
        (int256 highCoefficient, int256 highExponent) = LibDecimalFloatImplementation.pow10(x + gap, -70);
        assertTrue(
            LibTestErrorBound.monotoneRelative(
                LibDecimalFloat.packLossless(lowCoefficient, lowExponent),
                LibDecimalFloat.packLossless(highCoefficient, highExponent),
                LibTestErrorBound.pow10(),
                LibTestErrorBound.pow10()
            ),
            "monotone"
        );
    }
}
