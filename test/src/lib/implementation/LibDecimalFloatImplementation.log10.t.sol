// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {LibDecimalFloatImplementation, LOG10_RAW_ERROR} from "src/lib/implementation/LibDecimalFloatImplementation.sol";
import {Test, console2} from "forge-std-1.17.0/src/Test.sol";
import {Log10Zero, Log10Negative} from "src/error/ErrDecimalFloat.sol";
import {LibTranscendentalOracle, ORACLE_ONE, ORACLE_LN10} from "../../../lib/LibTranscendentalOracle.sol";
import {Math} from "@openzeppelin-contracts-5.7.0/utils/math/Math.sol";
import {LibDecimalFloat, Float} from "src/lib/LibDecimalFloat.sol";
import {LibTestErrorBound} from "../../../lib/LibTestErrorBound.sol";

contract LibDecimalFloatImplementationLog10Test is Test {
    function checkLog10(
        int256 signedCoefficient,
        int256 exponent,
        int256 expectedSignedCoefficient,
        int256 expectedExponent
    ) internal view {
        uint256 aGas = gasleft();
        (int256 actualSignedCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10(signedCoefficient, exponent);
        uint256 bGas = gasleft();
        // this is just a log, if the cast causes problems then the dev can
        // deal with it.
        // forge-lint: disable-next-line(unsafe-typecast)
        console2.log("%d %d Gas used: %d", uint256(signedCoefficient), uint256(exponent), aGas - bGas);
        assertEq(actualSignedCoefficient, expectedSignedCoefficient);
        assertEq(actualExponent, expectedExponent);
    }

    function testExactLogs() external view {
        checkLog10(1, 0, 0, 0);
        checkLog10(10, 0, 1, 0);
        checkLog10(100, 0, 2, 0);
        checkLog10(1000, 0, 3, 0);
        checkLog10(10000, 0, 4, 0);
        checkLog10(1e37, -37, 0, 0);
        checkLog10(1e76, -76, 0, 0);
    }

    /// |actual - reference| <= bound, all as floats.
    function assertErrorWithin(
        int256 signedCoefficient,
        int256 exponent,
        int256[4] memory expected,
        int256 boundCoefficient,
        int256 boundExponent
    ) internal pure {
        (int256 errorCoefficient, int256 errorExponent) =
            LibDecimalFloatImplementation.sub(signedCoefficient, exponent, expected[2], expected[3]);
        if (errorCoefficient < 0) {
            errorCoefficient = -errorCoefficient;
        }
        assertTrue(
            LibDecimalFloatImplementation.lte(errorCoefficient, errorExponent, boundCoefficient, boundExponent),
            "log10 error"
        );
    }

    /// Away from powers of ten the error is within `LOG10_RAW_ERROR` units of
    /// 1e-50, and the 70 digit references are within 1e-67.
    function testLog10Accuracy() external pure {
        int256[4][] memory references = log10References();
        for (uint256 i = 0; i < references.length; i++) {
            (int256 signedCoefficient, int256 exponent) =
                LibDecimalFloatImplementation.log10Unrounded(references[i][0], references[i][1]);
            // forge-lint: disable-next-line(unsafe-typecast)
            assertErrorWithin(signedCoefficient, exponent, references[i], int256(LOG10_RAW_ERROR) * 1e17 + 1, -67);
        }
    }

    /// Within a factor 1.001 of a power of ten the seed is exact, so the error
    /// is relative to the log, which can be arbitrarily close to zero:
    /// `log10Ratio`'s 9.6e-50 relative plus a unit of its quotient, which is at
    /// least 1e75 (2 / ln 10) / 2e76, 4.34e48, so 3.27e-49 relative.
    function testLog10AccuracyNearPowersOfTen() external pure {
        int256[4][] memory references = log10NearPowerOfTenReferences();
        for (uint256 i = 0; i < references.length; i++) {
            (int256 signedCoefficient, int256 exponent) =
                LibDecimalFloatImplementation.log10Unrounded(references[i][0], references[i][1]);
            (int256 boundCoefficient, int256 boundExponent) =
                LibDecimalFloatImplementation.mul(references[i][2], references[i][3], 327, -51);
            if (boundCoefficient < 0) {
                boundCoefficient = -boundCoefficient;
            }
            assertErrorWithin(signedCoefficient, exponent, references[i], boundCoefficient, boundExponent);
        }
    }

    /// The log is within about 1e-46 relative of the power it came from, far
    /// inside half a unit in the 41st digit, so a value with at most 41
    /// significant digits comes back exactly.
    function testLog10Pow10RoundTrip(uint256 coefficientSeed, int256 exponent) external pure {
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(bound(coefficientSeed, 1, 1e41 - 1));
        exponent = bound(exponent, type(int32).min, type(int32).max - 41);
        (int256 logCoefficient, int256 logExponent) =
            LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
        (int256 powerCoefficient, int256 powerExponent) =
            LibDecimalFloatImplementation.pow10(logCoefficient, logExponent);
        assertTrue(LibDecimalFloatImplementation.eq(powerCoefficient, powerExponent, signedCoefficient, exponent));
    }

    /// log10 is within its proven bound of the 70 digit reference, plus a
    /// unit in the reference's last place.
    function checkLog10WithinBound(int256[4][] memory references) internal pure {
        for (uint256 i = 0; i < references.length; i++) {
            (int256 signedCoefficient, int256 exponent) =
                LibDecimalFloatImplementation.log10(references[i][0], references[i][1]);
            (int256 boundCoefficient, int256 boundExponent) = LibDecimalFloat.unpack(
                LibTestErrorBound.log10(LibDecimalFloat.packLossless(signedCoefficient, exponent))
            );
            (boundCoefficient, boundExponent) =
                LibDecimalFloatImplementation.add(boundCoefficient, boundExponent, 1, references[i][3]);
            assertErrorWithin(signedCoefficient, exponent, references[i], boundCoefficient, boundExponent);
        }
    }

    function testLog10WithinBound() external pure {
        checkLog10WithinBound(log10References());
    }

    function testLog10WithinBoundNearPowersOfTen() external pure {
        checkLog10WithinBound(log10NearPowerOfTenReferences());
    }

    /// Inputs and their log10 to 70 significant digits from `bc -l` at scale
    /// 220, as (input coefficient, input exponent, log coefficient, log
    /// exponent).
    function log10References() internal pure returns (int256[4][] memory references) {
        references = new int256[4][](54);
        references[0] = [int256(1001), -3, 4340774793186406689213877779888660200037751774867729013649473955595637, -73];
        references[1] = [int256(2), 0, 3010299956639811952137388947244930267681898814621085413104274611271081, -70];
        references[2] = [
            int256(314159265358979323846264338327950288419716939937510582097494459),
            -62,
            4971498726941338543512682882908988736516783243804424461340534996059140,
            -70
        ];
        references[3] =
            [int256(99989999), -7, 9999565640368133109481630218366384434917489839401470218824207024630834, -70];
        references[4] = [int256(5), -1, -3010299956639811952137388947244930267681898814621085413104274611271081, -70];
        references[5] = [
            int256(123456789), -2147483600, -2147483591908485022830729552481666376940452741484926661055333569707647, -60
        ];
        references[6] = [
            int256(987654321), 2147483600, 2147483608994604968118722517484861789742258546185279826484283904994764, -60
        ];
        references[7] = [
            int256(13479973333575319897333507543509815336818572211270286240551805124607),
            0,
            6712968903306780653266377352356194496930634356605020471222532383134509,
            -68
        ];
        references[8] = [
            int256(13479973333575319897333507543509815336818572211270286240551805124607),
            -2147483648,
            -2147483580870310966932193467336226476438055030693656433949795287774676,
            -60
        ];
        references[9] =
            [int256(1), -2147483648, -2147483648000000000000000000000000000000000000000000000000000000000000, -60];
        references[10] =
            [int256(1), 2147483647, 2147483647000000000000000000000000000000000000000000000000000000000000, -60];
        references[11] = [int256(6566), 0, 3817300878393321290787303041135833994684960754678653223435613370063655, -69];
        references[12] = [int256(20), 0, 1301029995663981195213738894724493026768189881462108541310427461127108, -69];
        references[13] = [int256(9), -1, -4575749056067512540994419348976938159974227161860827034026871938954169, -71];
        references[14] = [
            int256(6562305898749053633841281509290),
            -36,
            -5182943529048673619907272007449280771305159988520354867341246062271756,
            -69
        ];
        references[15] = [
            int256(3124611797498107267682563018581),
            18,
            4849479606818342487736518921602824852603363673463063528436493667143369,
            -68
        ];
        references[16] = [
            int256(8686917696247160901523844527872),
            -49,
            -1806113429316814895226001699926417875358624563909350816591207402236001,
            -68
        ];
        references[17] = [
            int256(5249223594996214535365126037162),
            5,
            3572009507229278362734679375255593987140929939360805161256858590819643,
            -68
        ];
        references[18] = [
            int256(1811529493745268169206407546453),
            -62,
            -3174195459076742515165174039978598506554457226689963675040826131161940,
            -68
        ];
        references[19] = [
            int256(7373835392494321803047689055744),
            -8,
            2286769343854141431414192889836219181699464637703137729173063656323471,
            -68
        ];
        references[20] = [
            int256(3936141291243375436888970565035),
            -75,
            -4440492932057961771512065890819071359462658339719669573796726496894596,
            -68
        ];
        references[21] = [
            int256(9498447189992429070730252074325),
            -21,
            9977652612453223902341159132157696704761505489356258517312671382302945,
            -69
        ];
        references[22] = [
            int256(6060753088741482704571533583616),
            -88,
            -5721747340851289870893537264003013649467970175462557451366377266932570,
            -68
        ];
        references[23] = [
            int256(2623058987490536338412815092907),
            -34,
            -3581191942862337910075998918410081202225377738023815299718444394720969,
            -69
        ];
        references[24] = [
            int256(8185364886239589972254096602198),
            20,
            5091303804410816037631406800208891490479098097494430072583456463593902,
            -68
        ];
        references[25] = [
            int256(4747670784988643606095378111488),
            -47,
            -1632351940370646022695878769586277241031122542244770890320764533572182,
            -68
        ];
        references[26] = [
            int256(1309976683737697239936659620779),
            7,
            3711726356572128063116640234988542703719394959131065947235234290524148,
            -68
        ];
        references[27] = [
            int256(6872282582486750873777941130070),
            -60,
            -2916289899098538663437270193897784502110274606338562176212182193855856,
            -68
        ];
        references[28] = [
            int256(3434588481235804507619222639361),
            -6,
            2453587470907101538501864714324017318870150634585647860426840780311990,
            -68
        ];
        references[29] = [
            int256(8996894379984858141460504148651),
            -73,
            -4204590737793794976497791958788539836886573668199208071090010755254238,
            -68
        ];
        references[30] = [
            int256(5559200278733911775301785657942),
            -19,
            1174501232044657735446676347619253464636291576525022727202366751565719,
            -68
        ];
        references[31] = [
            int256(2121506177482965409143067167233),
            -86,
            -5567335569930021334562753882741874380207373246357233709302502876003597,
            -68
        ];
        references[32] = [
            int256(7683812076232019042984348676524),
            -32,
            -1114423265264465314903267477666782679487269955904721863887515412583657,
            -69
        ];
        references[33] = [
            int256(4246117974981072676825630185814),
            22,
            5262799205652133702859076891644647497405802242493818342917277718024735,
            -68
        ];
        references[34] = [
            int256(9808423873730126310666911695105),
            -45,
            -1400840077426486324845286644863654033273407711584452127333684031149212,
            -68
        ];
        references[35] = [
            int256(6370729772479179944508193204396),
            9,
            3980418918398486487451777474292854893807454300209463527779305701191071,
            -68
        ];
        references[36] = [
            int256(2933035671228233578349474713687),
            -58,
            -2753268265514990153878639374106102325591426526069867200095892118916237,
            -68
        ];
        references[37] = [
            int256(8495341569977287212190756222977),
            -4,
            2692918084512079208308134569263196917233932678443226256687464884634963,
            -68
        ];
        references[38] = [
            int256(5057647468726340846032037732268),
            -71,
            -4029605144539939244428124186178905706109793200129406598660655614401228,
            -68
        ];
        references[39] = [
            int256(1619953367475394479873319241559),
            -17,
            1320950251297497376898400317515466374904218354938187056488264606253804,
            -68
        ];
        references[40] = [
            int256(7182259266224448113714600750850),
            -84,
            -5314373892170252299750089052456205829273213725722255035136993585671040,
            -68
        ];
        references[41] = [
            int256(3744565164973501747555882260140),
            -30,
            5734013928186752500239851225144369234061594558090055377146051160902008,
            -70
        ];
        references[42] = [
            int256(9306871063722555381397163769431),
            24,
            5496880369729077884778911221102702993850580257427946627467534462486091,
            -68
        ];
        references[43] = [
            int256(5869176962471609015238445278722),
            -43,
            -1223142279580823668648435389190124479487750251417553876799397995730455,
            -68
        ];
        references[44] = [
            int256(2431482861220662649079726788013),
            11,
            4138587121270595419609199089431388678003808888277403242784337418299769,
            -68
        ];
        references[45] = [
            int256(7993788759969716282921008297303),
            -56,
            -2509724733238209884592590808141275913530979767257911407337034010244974,
            -68
        ];
        references[46] = [
            int256(4556094658718769916762289806594),
            -2,
            2865859273852650279321007961759581360155938892353621361873038752728270,
            -68
        ];
        references[47] = [
            int256(1118400557467823550603571315885),
            -69,
            -3895140262512384153154120485571250413317070580382122618122386213376345,
            -68
        ];
        references[48] = [
            int256(6680706456216877184444852825176),
            -15,
            1582482238969323993782087277977391104874859978717659454533299366377547,
            -68
        ];
        references[49] = [
            int256(3243012354965930818286134334466),
            -82,
            -5148905139678391684271469151875674491337421641637358040855789892556524,
            -68
        ];
        references[50] = [
            int256(8805318253714984452127415843757),
            -28,
            2944745057445197040395140494729674573807397156353167416745729802261293,
            -69
        ];
        references[51] = [
            int256(5367624152464038085968697353048),
            26,
            5672978209840059648307885697872704739137340147117203450610701996252225,
            -68
        ];
        references[52] = [
            int256(1929930051213091719809978862338),
            -41,
            -1071445843136667363160716051805584069414844154821382449136180777328039,
            -68
        ];
        references[53] = [
            int256(7492235949962145353651260371629),
            13,
            4387461144597936061034254383551799199449440200935740373236705815624670,
            -68
        ];
    }

    /// As `log10References`, for inputs within a factor 1.001 of a power of ten.
    function log10NearPowerOfTenReferences() internal pure returns (int256[4][] memory references) {
        references = new int256[4][](8);
        references[0] = [
            int256(1000000000000000000000000000000000000000000000000000000000000000000001),
            -69,
            4342944819032518276511289189166050822943970058036665661144537831658644,
            -139
        ];
        references[1] = [
            int256(9999999999999999999999999999999999999999999999999999999999999999999),
            -67,
            -4342944819032518276511289189166050822943970058036665661144537831658863,
            -137
        ];
        references[2] = [
            int256(1000000000000000000001),
            -21,
            4342944819032518276509117716756534563805715861090355646572491349306955,
            -91
        ];
        references[3] = [int256(10005), -4, 2170929722302082819128837510668233837444349518373528604405734453955318, -73];
        references[4] =
            [int256(100099999999), -11, 4340774749800344560800178403509717564802174233195342567907169546786031, -73];
        references[5] = [int256(9999), -3, 9999565683801924896154439559761927733262492740542974156620889362386593, -70];
        references[6] =
            [int256(999999), -5, 9999995657053009493624557870824642416033630579158869140086417791048324, -70];
        references[7] = [
            int256(99999999999999999999999999999999999999999999999999999999999999),
            -61,
            9999999999999999999999999999999999999999999999999999999999999956570551,
            -70
        ];
    }

    function log10External(int256 signedCoefficient, int256 exponent) external pure returns (int256, int256) {
        return LibDecimalFloatImplementation.log10(signedCoefficient, exponent);
    }

    function testLog10ZeroReverts() external {
        vm.expectRevert(abi.encodeWithSelector(Log10Zero.selector));
        this.log10External(0, 0);
    }

    function testLog10NegativeReverts(int256 signedCoefficient, int256 exponent) external {
        signedCoefficient = bound(signedCoefficient, type(int256).min, -1);
        vm.expectRevert(abi.encodeWithSelector(Log10Negative.selector, signedCoefficient, exponent));
        this.log10External(signedCoefficient, exponent);
    }

    function testLog10One() external view {
        unchecked {
            int256 exponent = 0;
            for (int256 i = 1; exponent >= -76;) {
                checkLog10(i, exponent, 0, 0);
                exponent--;
                i *= 10;
            }
        }
    }

    function log10Either(int256 signedCoefficient, int256 exponent, bool rounded)
        internal
        pure
        returns (int256, int256)
    {
        return rounded
            ? LibDecimalFloatImplementation.log10(signedCoefficient, exponent)
            : LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
    }

    /// The exponent of a unit in the 41st significant digit of a nonzero
    /// float.
    function ulpExponent(int256 signedCoefficient, int256 exponent) internal pure returns (int256) {
        assertTrue(signedCoefficient != 0, "zero");
        for (
            int256 scaled = signedCoefficient < 0 ? -signedCoefficient : signedCoefficient;
            scaled < 1e40;
            scaled *= 10
        ) {
            exponent--;
        }
        return exponent;
    }

    /// |actual - expected| in billionths of a unit in the 41st significant
    /// digit of actual.
    function ulpBillionths(
        int256 actualCoefficient,
        int256 actualExponent,
        int256 expectedCoefficient,
        int256 expectedExponent
    ) internal pure returns (uint256) {
        (int256 errorCoefficient, int256 errorExponent) = LibDecimalFloatImplementation.sub(
            actualCoefficient, actualExponent, expectedCoefficient, expectedExponent
        );
        int256 error = LibDecimalFloatImplementation.withTargetExponent(
            errorCoefficient, errorExponent, ulpExponent(actualCoefficient, actualExponent) - 9
        );
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint256(error < 0 ? -error : error);
    }

    function prime(uint256 primeSeed) internal pure returns (uint256) {
        uint256[3] memory primes = [uint256(2), 3, 7];
        return primes[primeSeed % 3];
    }

    /// |log10(x) - oracle| for x = prime^j (1 ± d / 10^p) 10^n, which spreads
    /// the seed over the whole decade. Unrounded, in units of 1e-70. Rounded,
    /// in billionths of a unit in the result's last place, with n moved off 0
    /// when j is 0, as a log within log10(1.001) of zero is finer than the
    /// oracle's 1e-70. `log10NearOneUlpError` covers it.
    function log10OracleError(uint256 primeSeed, uint256 j, uint256 p, uint256 d, bool negative, int256 n, bool rounded)
        internal
        pure
        returns (uint256)
    {
        uint256 base = prime(primeSeed);
        j = bound(j, 0, LibTranscendentalOracle.maxPower(base));
        p = bound(p, 3, 40);
        d = bound(d, 0, 10 ** (p - 3));
        n = bound(n, -1e6, 1e6);
        if (rounded && j == 0 && n == 0) {
            n = 1;
        }
        // Below 1e30 * 1.001e40, so it fits.
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(base ** j * (negative ? 10 ** p - d : 10 ** p + d));
        (
            int256 logCoefficient,
            int256 logExponent
            // forge-lint: disable-next-line(unsafe-typecast)
        ) = log10Either(signedCoefficient, n - int256(p), rounded);
        int256 actual = logExponent >= -70
            // forge-lint: disable-next-line(unsafe-typecast)
            ? logCoefficient * int256(10 ** uint256(70 + logExponent))
            // forge-lint: disable-next-line(unsafe-typecast)
            : logCoefficient / int256(10 ** uint256(-70 - logExponent));
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 expected = int256(j * LibTranscendentalOracle.log10Prime(base)) + n * int256(ORACLE_ONE)
            + LibTranscendentalOracle.log10OnePlus(d, p, negative);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 error = uint256(actual > expected ? actual - expected : expected - actual);
        if (!rounded) {
            return error;
        }
        // The log is at least 3e-3 from zero, so its last place is above 1e-70.
        // forge-lint: disable-next-line(unsafe-typecast)
        return Math.mulDiv(error, 1e9, 10 ** uint256(70 + ulpExponent(logCoefficient, logExponent)));
    }

    /// Half a unit plus `LOG10_RAW_ERROR` units of 1e-50, which is 200
    /// billionths of a last place at least 1e-43. The oracle is within 101
    /// units of 1e-70: each truncated prime log is under a unit low and
    /// log10OnePlus is within 2. That is under 1e-16 billionths, and the
    /// billionths are floored.
    function testLog10OracleFuzz(uint256 primeSeed, uint256 j, uint256 p, uint256 d, bool negative, int256 n)
        external
        pure
    {
        assertLe(
            log10OracleError(primeSeed, j, p, d, negative, n, true), 500000000 + LOG10_RAW_ERROR * 100, "log10 error"
        );
    }

    /// `LOG10_RAW_ERROR` units of 1e-50, plus the oracle's 101 units of 1e-70
    /// and the unit the comparison truncates.
    function testLog10UnroundedOracleFuzz(uint256 primeSeed, uint256 j, uint256 p, uint256 d, bool negative, int256 n)
        external
        pure
    {
        assertLe(log10OracleError(primeSeed, j, p, d, negative, n, false), LOG10_RAW_ERROR * 1e20 + 102, "log10 error");
    }

    /// x = 1 ± d / 10^p, within a factor 1.001 of 1, and log10(x) from the
    /// oracle as a float.
    function nearOne(uint256 p, uint256 d, bool negative)
        internal
        pure
        returns (int256 signedCoefficient, int256 exponent, int256 expectedCoefficient, int256 expectedExponent)
    {
        p = bound(p, 4, 75);
        d = bound(d, 1, negative ? 10 ** (p - 4) : 10 ** (p - 3) - 1);
        // forge-lint: disable-next-line(unsafe-typecast)
        signedCoefficient = int256(negative ? 10 ** p - d : 10 ** p + d);
        // forge-lint: disable-next-line(unsafe-typecast)
        exponent = -int256(p);
        uint256 ratio = Math.mulDiv(LibTranscendentalOracle.lnOnePlusOverU(d, p, negative), ORACLE_ONE, ORACLE_LN10);
        // d and ratio are below 1e72.
        (expectedCoefficient, expectedExponent) = LibDecimalFloatImplementation.mul(
            // forge-lint: disable-next-line(unsafe-typecast)
            negative ? -int256(d) : int256(d),
            exponent,
            // forge-lint: disable-next-line(unsafe-typecast)
            int256(ratio),
            -70
        );
    }

    /// |log10Unrounded(x) / oracle - 1| for x near 1, as a float.
    function log10NearOneRelativeError(uint256 p, uint256 d, bool negative) internal pure returns (int256, int256) {
        (int256 signedCoefficient, int256 exponent, int256 expectedCoefficient, int256 expectedExponent) =
            nearOne(p, d, negative);
        (int256 actualCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
        (int256 errorCoefficient, int256 errorExponent) =
            LibDecimalFloatImplementation.sub(actualCoefficient, actualExponent, expectedCoefficient, expectedExponent);
        (errorCoefficient, errorExponent) =
            LibDecimalFloatImplementation.div(errorCoefficient, errorExponent, expectedCoefficient, expectedExponent);
        return (errorCoefficient < 0 ? -errorCoefficient : errorCoefficient, errorExponent);
    }

    /// 3.27e-49 relative, as `testLog10AccuracyNearPowersOfTen`. The oracle is
    /// within 5e-69 relative.
    function testLog10UnroundedNearOneOracleFuzz(uint256 p, uint256 d, bool negative) external pure {
        (int256 errorCoefficient, int256 errorExponent) = log10NearOneRelativeError(p, d, negative);
        assertTrue(LibDecimalFloatImplementation.lte(errorCoefficient, errorExponent, 327, -51), "log10 relative error");
    }

    /// |log10(x) - oracle| for x near 1, in billionths of a unit in the
    /// result's last place.
    function log10NearOneUlpError(uint256 p, uint256 d, bool negative) internal pure returns (uint256) {
        (int256 signedCoefficient, int256 exponent, int256 expectedCoefficient, int256 expectedExponent) =
            nearOne(p, d, negative);
        (int256 actualCoefficient, int256 actualExponent) =
            LibDecimalFloatImplementation.log10(signedCoefficient, exponent);
        return ulpBillionths(actualCoefficient, actualExponent, expectedCoefficient, expectedExponent);
    }

    /// Half a unit plus 3.27e-49 relative, which is 32.7 billionths of a last
    /// place at least 1e-41 relative. The oracle's 5e-69 relative is under
    /// 1e-18 billionths, and the billionths are floored.
    function testLog10NearOneOracleFuzz(uint256 p, uint256 d, bool negative) external pure {
        assertLe(log10NearOneUlpError(p, d, negative), 500000032, "log10 error");
    }

    /// log10 is log10Unrounded rounded to nearest, so within half a unit.
    function testLog10RoundsUnrounded(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, -1e40, 1e40);
        (int256 unroundedCoefficient, int256 unroundedExponent) =
            LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
        (int256 logCoefficient, int256 logExponent) = LibDecimalFloatImplementation.log10(signedCoefficient, exponent);
        if (logCoefficient == 0) {
            assertEq(unroundedCoefficient, 0, "zero");
            return;
        }
        assertLe(ulpBillionths(logCoefficient, logExponent, unroundedCoefficient, unroundedExponent), 500000000, "half");
    }

    /// log10Unrounded(x 10^k) = log10Unrounded(x) + k exactly, as the
    /// characteristic is summed as an integer, except that a log within
    /// log10(1.001) of zero keeps digits below the 1e-50 its shift truncates
    /// to.
    function testLog10DecadeShift(int256 signedCoefficient, int256 exponent, int256 shift) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, -1e18, 1e18);
        shift = bound(shift, -1e18, 1e18);
        (int256 logCoefficient, int256 logExponent) =
            LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent);
        (int256 shiftedCoefficient, int256 shiftedExponent) =
            LibDecimalFloatImplementation.log10Unrounded(signedCoefficient, exponent + shift);
        (logCoefficient, logExponent) = LibDecimalFloatImplementation.add(logCoefficient, logExponent, shift, 0);
        if (logExponent < -50 || shiftedExponent < -50) {
            (int256 errorCoefficient, int256 errorExponent) =
                LibDecimalFloatImplementation.sub(shiftedCoefficient, shiftedExponent, logCoefficient, logExponent);
            assertTrue(
                LibDecimalFloatImplementation.lt(
                    errorCoefficient < 0 ? -errorCoefficient : errorCoefficient, errorExponent, 1, -50
                ),
                "near zero shift"
            );
        } else {
            assertTrue(
                LibDecimalFloatImplementation.eq(shiftedCoefficient, shiftedExponent, logCoefficient, logExponent),
                "shift"
            );
        }
    }

    /// k <= log10(x) <= k + 1 for x in [10^k, 10^(k+1)), over every positive
    /// coefficient and exponents past the 1e25 characteristic that leaves the
    /// fixed point sum.
    function testLog10Bracket(int256 signedCoefficient, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1, type(int256).max);
        exponent = bound(exponent, -1e40, 1e40);
        int256 characteristic = exponent;
        for (int256 scaled = signedCoefficient / 10; scaled > 0; scaled /= 10) {
            characteristic++;
        }
        (int256 logCoefficient, int256 logExponent) = LibDecimalFloatImplementation.log10(signedCoefficient, exponent);
        assertTrue(LibDecimalFloatImplementation.gte(logCoefficient, logExponent, characteristic, 0), "floor");
        assertTrue(LibDecimalFloatImplementation.lte(logCoefficient, logExponent, characteristic + 1, 0), "ceiling");
    }

    /// log10(10^k) = k exactly, written with any number of trailing zeros.
    function testLog10PowersOfTenExact(uint256 zeros, int256 exponent) external pure {
        zeros = bound(zeros, 0, 76);
        exponent = bound(exponent, -1e40, 1e40);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 signedCoefficient = int256(10 ** zeros);
        (int256 logCoefficient, int256 logExponent) = LibDecimalFloatImplementation.log10(signedCoefficient, exponent);
        // forge-lint: disable-next-line(unsafe-typecast)
        assertTrue(LibDecimalFloatImplementation.eq(logCoefficient, logExponent, exponent + int256(zeros), 0));
    }

    /// x < y implies log10(x) <= log10(y) + 2E, down to adjacent 76 digit
    /// coefficients, whose logs differ by far less than a unit in the last place.
    function testLog10Monotone(int256 signedCoefficient, int256 gap, int256 exponent) external pure {
        signedCoefficient = bound(signedCoefficient, 1e75, 1e76 - 1e3);
        gap = bound(gap, 1, 1e3);
        exponent = bound(exponent, -1e6, 1e6);
        (int256 lowCoefficient, int256 lowExponent) = LibDecimalFloatImplementation.log10(signedCoefficient, exponent);
        (int256 highCoefficient, int256 highExponent) =
            LibDecimalFloatImplementation.log10(signedCoefficient + gap, exponent);
        Float low = LibDecimalFloat.packLossless(lowCoefficient, lowExponent);
        Float high = LibDecimalFloat.packLossless(highCoefficient, highExponent);
        assertTrue(
            LibTestErrorBound.monotoneAbsolute(low, high, LibTestErrorBound.log10(low), LibTestErrorBound.log10(high)),
            "monotone"
        );
    }

    /// Coefficients too small to take their full shift at the floor.
    /// log10(c * 10^e) = log10(c) + e, which for e within 76 of int256.min
    /// rounds at 41 digits to the same value as int256.min itself, from `bc`:
    /// -57896044618658097711785492504343953926634|992332820282019728792003956564819968.
    function testLog10AtFloor() external view {
        int256 min = type(int256).min;
        int256 rounded = -57896044618658097711785492504343953926635;
        checkLog10(1, min, rounded, 36);
        checkLog10(10, min, rounded, 36);
        checkLog10(1e75, min, rounded, 36);
        checkLog10(1, min + 1, rounded, 36);
        checkLog10(1, min + 75, rounded, 36);
        checkLog10(2, min, rounded, 36);
        checkLog10(2, min + 1, rounded, 36);
        checkLog10(5e75, min, rounded, 36);
    }

    /// Near the floor, log10(c * 10^e) = log10(c) + e is in [min + 3, min + 61]
    /// for c up to 1e10, and the 36 digits of int256.min below its 41st are
    /// 992332820282019728792003956564819968, so every such log rounds at 41
    /// digits to the same value as int256.min.
    function testLog10NearFloorMatchesShifted(int256 signedCoefficient, uint256 headroom) external view {
        signedCoefficient = bound(signedCoefficient, 1, 1e10);
        // forge-lint: disable-next-line(unsafe-typecast)
        int256 exponent = type(int256).min + int256(bound(headroom, 3, 50));
        checkLog10(signedCoefficient, exponent, -57896044618658097711785492504343953926635, 36);
    }
}
