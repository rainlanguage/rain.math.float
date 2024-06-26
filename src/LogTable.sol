// SPDX-License-Identifier: CAL
pragma solidity ^0.8.25;

import {console} from "forge-std/console.sol";

library LibLogTable {

    function toBytes(uint16[10][90] memory table) internal view returns (bytes memory) {
        uint256 v;
        bytes memory encoded;
        assembly ("memory-safe") {
            v := mload(add(mload(table), 0x20))

            encoded := mload(0x40)
            mstore(0x40, add(encoded, add(1800, 0x20)))

            cursor := sub(mload(0x40), 0x20)

        }
        console.log("v", v);

        return abi.encodePacked(table);
    }

    function logTableDec() internal pure returns (uint16[10][90] memory) {
        return [
            [0, 43, 86, 128, 170, 212, 253, 294, 334, 374],
            [414, 453, 492, 531, 569, 607, 645, 682, 719, 755],
            [792, 828, 864, 899, 934, 969, 1004, 1038, 1072, 1106],
            [1139, 1173, 1206, 1239, 1271, 1303, 1335, 1367, 1399, 1430],
            [1461, 1492, 1523, 1553, 1584, 1614, 1644, 1673, 1703, 1732],
            [1761, 1790, 1818, 1847, 1875, 1903, 1931, 1959, 1987, 2014],
            [2041, 2068, 2095, 2122, 2148, 2175, 2201, 2227, 2253, 2279],
            [2304, 2330, 2355, 2380, 2405, 2430, 2455, 2480, 2504, 2529],
            [2553, 2577, 2601, 2625, 2648, 2672, 2695, 2718, 2742, 2765],
            [2788, 2810, 2833, 2856, 2878, 2900, 2923, 2945, 2967, 2989],
            [3010, 3032, 3054, 3075, 3096, 3118, 3139, 3160, 3181, 3201],
            [3222, 3243, 3263, 3284, 3304, 3324, 3345, 3365, 3385, 3404],
            [3424, 3444, 3464, 3483, 3502, 3522, 3541, 3560, 3579, 3598],
            [3617, 3636, 3655, 3674, 3692, 3711, 3729, 3747, 3766, 3784],
            [3802, 3820, 3838, 3856, 3874, 3892, 3909, 3927, 3945, 3962],
            [3979, 3997, 4014, 4031, 4048, 4065, 4082, 4099, 4116, 4133],
            [4150, 4166, 4183, 4200, 4216, 4232, 4249, 4265, 4281, 4298],
            [4314, 4330, 4346, 4362, 4378, 4393, 4409, 4425, 4440, 4456],
            [4472, 4487, 4502, 4518, 4533, 4548, 4564, 4579, 4594, 4609],
            [4624, 4639, 4654, 4669, 4683, 4698, 4713, 4728, 4742, 4757],
            [4771, 4786, 4800, 4814, 4829, 4843, 4857, 4871, 4886, 4900],
            [4914, 4928, 4942, 4955, 4969, 4983, 4997, 5011, 5024, 5038],
            [5051, 5065, 5079, 5092, 5105, 5119, 5132, 5145, 5159, 5172],
            [5185, 5198, 5211, 5224, 5237, 5250, 5263, 5276, 5289, 5302],
            [5315, 5328, 5340, 5353, 5366, 5378, 5391, 5403, 5416, 5428],
            [5441, 5453, 5465, 5478, 5490, 5502, 5514, 5527, 5539, 5551],
            [5563, 5575, 5587, 5599, 5611, 5623, 5635, 5647, 5658, 5670],
            [5682, 5694, 5705, 5717, 5729, 5740, 5752, 5763, 5775, 5786],
            [5798, 5809, 5821, 5832, 5843, 5855, 5866, 5877, 5888, 5899],
            [5911, 5922, 5933, 5944, 5955, 5966, 5977, 5988, 5999, 6010],
            [6021, 6031, 6042, 6053, 6064, 6075, 6085, 6096, 6107, 6117],
            [6128, 6138, 6149, 6160, 6170, 6180, 6191, 6201, 6212, 6222],
            [6232, 6243, 6253, 6263, 6274, 6284, 6294, 6304, 6314, 6325],
            [6335, 6345, 6355, 6365, 6375, 6385, 6395, 6405, 6415, 6425],
            [6435, 6444, 6454, 6464, 6474, 6484, 6493, 6503, 6513, 6522],
            [6532, 6542, 6551, 6561, 6571, 6580, 6590, 6599, 6609, 6618],
            [6628, 6637, 6646, 6656, 6665, 6675, 6684, 6693, 6702, 6712],
            [6721, 6730, 6739, 6749, 6758, 6767, 6776, 6785, 6794, 6803],
            [6812, 6821, 6830, 6839, 6848, 6857, 6866, 6875, 6884, 6893],
            [6902, 6911, 6920, 6928, 6937, 6946, 6955, 6964, 6972, 6981],
            [6990, 6998, 7007, 7016, 7024, 7033, 7042, 7050, 7059, 7067],
            [7076, 7084, 7093, 7101, 7110, 7118, 7126, 7135, 7143, 7152],
            [7160, 7168, 7177, 7185, 7193, 7202, 7210, 7218, 7226, 7235],
            [7243, 7251, 7259, 7267, 7275, 7284, 7292, 7300, 7308, 7316],
            [7324, 7332, 7340, 7348, 7356, 7364, 7372, 7380, 7388, 7396],
            [7404, 7412, 7419, 7427, 7435, 7443, 7451, 7459, 7466, 7474],
            [7482, 7490, 7497, 7505, 7513, 7520, 7528, 7536, 7543, 7551],
            [7559, 7566, 7574, 7582, 7589, 7597, 7604, 7612, 7619, 7627],
            [7634, 7642, 7649, 7657, 7664, 7672, 7679, 7686, 7694, 7701],
            [7709, 7716, 7723, 7731, 7738, 7745, 7752, 7760, 7767, 7774],
            [7782, 7789, 7796, 7803, 7810, 7818, 7825, 7832, 7839, 7846],
            [7853, 7860, 7868, 7875, 7882, 7889, 7896, 7903, 7910, 7917],
            [7924, 7931, 7938, 7945, 7952, 7959, 7966, 7973, 7980, 7987],
            [7993, 8000, 8007, 8014, 8021, 8028, 8035, 8041, 8048, 8055],
            [8062, 8069, 8075, 8082, 8089, 8096, 8102, 8109, 8116, 8122],
            [8129, 8136, 8142, 8149, 8156, 8162, 8169, 8176, 8182, 8189],
            [8195, 8202, 8209, 8215, 8222, 8228, 8235, 8241, 8248, 8254],
            [8261, 8267, 8274, 8280, 8287, 8293, 8299, 8306, 8312, 8319],
            [8325, 8331, 8338, 8344, 8351, 8357, 8363, 8370, 8376, 8382],
            [8388, 8395, 8401, 8407, 8414, 8420, 8426, 8432, 8439, 8445],
            [8451, 8457, 8463, 8470, 8476, 8482, 8488, 8494, 8500, 8506],
            [8513, 8519, 8525, 8531, 8537, 8543, 8549, 8555, 8561, 8567],
            [8573, 8579, 8585, 8591, 8597, 8603, 8609, 8615, 8621, 8627],
            [8633, 8639, 8645, 8651, 8657, 8663, 8669, 8675, 8681, 8686],
            [8692, 8698, 8704, 8710, 8716, 8722, 8727, 8733, 8739, 8745],
            [8751, 8756, 8762, 8768, 8774, 8779, 8785, 8791, 8797, 8802],
            [8808, 8814, 8820, 8825, 8831, 8837, 8842, 8848, 8854, 8859],
            [8865, 8871, 8876, 8882, 8887, 8893, 8899, 8904, 8910, 8915],
            [8921, 8927, 8932, 8938, 8943, 8949, 8954, 8960, 8965, 8971],
            [8976, 8982, 8987, 8993, 8998, 9004, 9009, 9015, 9020, 9025],
            [9031, 9036, 9042, 9047, 9053, 9058, 9063, 9069, 9074, 9079],
            [9085, 9090, 9096, 9101, 9106, 9112, 9117, 9122, 9128, 9133],
            [9138, 9143, 9149, 9154, 9159, 9165, 9170, 9175, 9180, 9186],
            [9191, 9196, 9201, 9206, 9212, 9217, 9222, 9227, 9232, 9238],
            [9243, 9248, 9253, 9258, 9263, 9269, 9274, 9279, 9284, 9289],
            [9294, 9299, 9304, 9309, 9315, 9320, 9325, 9330, 9335, 9340],
            [9345, 9350, 9355, 9360, 9365, 9370, 9375, 9380, 9385, 9390],
            [9395, 9400, 9405, 9410, 9415, 9420, 9425, 9430, 9435, 9440],
            [9445, 9450, 9455, 9460, 9465, 9469, 9474, 9479, 9484, 9489],
            [9494, 9499, 9504, 9509, 9513, 9518, 9523, 9528, 9533, 9538],
            [9542, 9547, 9552, 9557, 9562, 9566, 9571, 9576, 9581, 9586],
            [9590, 9595, 9600, 9605, 9609, 9614, 9619, 9624, 9628, 9633],
            [9638, 9643, 9647, 9652, 9657, 9661, 9666, 9671, 9675, 9680],
            [9685, 9689, 9694, 9699, 9703, 9708, 9713, 9717, 9722, 9727],
            [9731, 9736, 9741, 9745, 9750, 9754, 9759, 9763, 9768, 9773],
            [9777, 9782, 9786, 9791, 9795, 9800, 9805, 9809, 9814, 9818],
            [9823, 9827, 9832, 9836, 9841, 9845, 9850, 9854, 9859, 9863],
            [9868, 9872, 9877, 9881, 9886, 9890, 9894, 9899, 9903, 9908],
            [9912, 9917, 9921, 9926, 9930, 9934, 9939, 9943, 9948, 9952],
            [9956, 9961, 9965, 9969, 9974, 9978, 9983, 9987, 9991, 9996]
        ];
    }

    function logTableDecSmall() internal pure returns (uint8[10][90] memory) {
        return [
            [0, 4, 9, 13, 17, 21, 26, 30, 34, 38],
            [0, 4, 8, 12, 15, 19, 23, 27, 31, 35],
            [0, 3, 7, 11, 14, 18, 21, 25, 28, 32],
            [0, 3, 7, 10, 13, 16, 20, 23, 26, 30],
            [0, 3, 6, 9, 12, 15, 18, 21, 24, 28],
            [0, 3, 6, 9, 11, 14, 17, 20, 23, 26],
            [0, 3, 5, 8, 11, 14, 16, 19, 22, 24],
            [0, 3, 5, 8, 10, 13, 15, 18, 20, 23],
            [0, 2, 5, 7, 9, 12, 14, 16, 19, 21],
            [0, 2, 4, 7, 9, 11, 13, 16, 18, 20],
            [0, 2, 4, 6, 8, 11, 13, 15, 17, 19],
            [0, 2, 4, 6, 8, 10, 12, 14, 16, 18],
            [0, 2, 4, 6, 8, 10, 12, 14, 15, 17],
            [0, 2, 4, 6, 7, 9, 11, 13, 15, 17],
            [0, 2, 4, 5, 7, 9, 11, 12, 14, 16],
            [0, 2, 3, 5, 7, 9, 10, 12, 14, 15],
            [0, 2, 3, 5, 7, 8, 10, 11, 13, 15],
            [0, 2, 3, 5, 6, 8, 9, 11, 13, 14],
            [0, 2, 3, 5, 6, 8, 9, 11, 12, 14],
            [0, 1, 3, 4, 6, 7, 9, 10, 12, 13],
            [0, 1, 3, 4, 6, 7, 9, 10, 11, 13],
            [0, 1, 3, 4, 6, 7, 8, 10, 11, 12],
            [0, 1, 3, 4, 5, 7, 8, 9, 11, 12],
            [0, 1, 3, 4, 5, 6, 8, 9, 10, 12],
            [0, 1, 3, 4, 5, 6, 8, 9, 10, 11],
            [0, 1, 2, 4, 5, 6, 7, 9, 10, 11],
            [0, 1, 2, 4, 5, 6, 7, 8, 10, 11],
            [0, 1, 2, 3, 5, 6, 7, 8, 9, 10],
            [0, 1, 2, 3, 5, 6, 7, 8, 9, 10],
            [0, 1, 2, 3, 4, 5, 7, 8, 9, 10],
            [0, 1, 2, 3, 4, 5, 6, 8, 9, 10],
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [0, 1, 2, 3, 4, 5, 6, 7, 7, 8],
            [0, 1, 2, 3, 4, 5, 5, 6, 7, 8],
            [0, 1, 2, 3, 4, 4, 5, 6, 7, 8],
            [0, 1, 2, 3, 4, 4, 5, 6, 7, 8],
            [0, 1, 2, 3, 3, 4, 5, 6, 7, 8],
            [0, 1, 2, 3, 3, 4, 5, 6, 7, 8],
            [0, 1, 2, 2, 3, 4, 5, 6, 7, 7],
            [0, 1, 2, 2, 3, 4, 5, 6, 6, 7],
            [0, 1, 2, 2, 3, 4, 5, 6, 6, 7],
            [0, 1, 2, 2, 3, 4, 5, 5, 6, 7],
            [0, 1, 2, 2, 3, 4, 5, 5, 6, 7],
            [0, 1, 2, 2, 3, 4, 5, 5, 6, 7],
            [0, 1, 1, 2, 3, 4, 4, 5, 6, 7],
            [0, 1, 1, 2, 3, 4, 4, 5, 6, 7],
            [0, 1, 1, 2, 3, 4, 4, 5, 6, 6],
            [0, 1, 1, 2, 3, 4, 4, 5, 6, 6],
            [0, 1, 1, 2, 3, 3, 4, 5, 6, 6],
            [0, 1, 1, 2, 3, 3, 4, 5, 5, 6],
            [0, 1, 1, 2, 3, 3, 4, 5, 5, 6],
            [0, 1, 1, 2, 3, 3, 4, 5, 5, 6],
            [0, 1, 1, 2, 3, 3, 4, 5, 5, 6],
            [0, 1, 1, 2, 3, 3, 4, 5, 5, 6],
            [0, 1, 1, 2, 3, 3, 4, 4, 5, 6],
            [0, 1, 1, 2, 2, 3, 4, 4, 5, 6],
            [0, 1, 1, 2, 2, 3, 4, 4, 5, 6],
            [0, 1, 1, 2, 2, 3, 4, 4, 5, 5],
            [0, 1, 1, 2, 2, 3, 4, 4, 5, 5],
            [0, 1, 1, 2, 2, 3, 4, 4, 5, 5],
            [0, 1, 1, 2, 2, 3, 4, 4, 5, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 5, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 5, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 3, 4]
        ];
    }

    function logTableSmallAlt() internal pure returns (uint8[10][10] memory) {
        return [
            [0, 4, 8, 12, 16, 20, 24, 28, 32, 37],
            [0, 4, 7, 11, 15, 19, 22, 26, 30, 33],
            [0, 3, 7, 10, 14, 17, 20, 24, 27, 31],
            [0, 3, 7, 10, 12, 16, 19, 22, 25, 29],
            [0, 3, 6, 9, 12, 15, 17, 20, 23, 26],
            [0, 3, 5, 8, 11, 14, 16, 19, 22, 25],
            [0, 3, 5, 8, 10, 13, 15, 18, 21, 23],
            [0, 2, 5, 7, 10, 12, 15, 17, 19, 22],
            [0, 2, 5, 7, 9, 11, 14, 16, 18, 21],
            [0, 2, 4, 6, 8, 11, 13, 15, 17, 19]
        ];
    }

    function antiLogTableDec() internal pure returns (uint16[10][100] memory) {
        return [
            [1000, 1002, 1005, 1007, 1009, 1012, 1014, 1016, 1019, 1021],
            [1023, 1026, 1028, 1030, 1033, 1035, 1038, 1040, 1042, 1045],
            [1047, 1050, 1052, 1054, 1057, 1059, 1062, 1064, 1067, 1069],
            [1072, 1074, 1076, 1079, 1081, 1084, 1086, 1089, 1091, 1094],
            [1096, 1099, 1102, 1104, 1107, 1109, 1112, 1114, 1117, 1119],
            [1122, 1125, 1127, 1130, 1132, 1135, 1138, 1140, 1143, 1146],
            [1148, 1151, 1153, 1156, 1159, 1161, 1164, 1167, 1169, 1172],
            [1175, 1178, 1180, 1183, 1186, 1189, 1191, 1194, 1197, 1199],
            [1202, 1205, 1208, 1211, 1213, 1216, 1219, 1222, 1225, 1227],
            [1230, 1233, 1236, 1239, 1242, 1245, 1247, 1250, 1253, 1256],
            [1259, 1262, 1265, 1268, 1271, 1274, 1276, 1279, 1282, 1285],
            [1288, 1291, 1294, 1297, 1300, 1303, 1306, 1309, 1312, 1315],
            [1318, 1321, 1324, 1327, 1330, 1334, 1337, 1340, 1343, 1346],
            [1349, 1352, 1355, 1358, 1361, 1365, 1368, 1371, 1374, 1377],
            [1380, 1384, 1387, 1390, 1393, 1396, 1400, 1403, 1406, 1409],
            [1413, 1416, 1419, 1422, 1426, 1429, 1432, 1435, 1439, 1442],
            [1445, 1449, 1452, 1455, 1459, 1462, 1466, 1469, 1472, 1476],
            [1479, 1483, 1486, 1489, 1493, 1496, 1500, 1503, 1507, 1510],
            [1514, 1517, 1521, 1524, 1528, 1531, 1535, 1538, 1542, 1545],
            [1549, 1552, 1556, 1560, 1563, 1567, 1570, 1574, 1578, 1581],
            [1585, 1589, 1592, 1596, 1600, 1603, 1607, 1611, 1614, 1618],
            [1622, 1626, 1629, 1633, 1637, 1641, 1644, 1648, 1652, 1656],
            [1660, 1663, 1667, 1671, 1675, 1679, 1683, 1687, 1690, 1694],
            [1698, 1702, 1706, 1710, 1714, 1718, 1722, 1726, 1730, 1734],
            [1738, 1742, 1746, 1750, 1754, 1758, 1762, 1766, 1770, 1774],
            [1778, 1782, 1786, 1791, 1795, 1799, 1803, 1807, 1811, 1816],
            [1820, 1824, 1828, 1832, 1837, 1841, 1845, 1849, 1854, 1858],
            [1862, 1866, 1871, 1875, 1879, 1884, 1888, 1892, 1897, 1901],
            [1905, 1910, 1914, 1919, 1923, 1928, 1932, 1936, 1941, 1945],
            [1950, 1954, 1959, 1963, 1968, 1972, 1977, 1982, 1986, 1991],
            [1995, 2000, 2004, 2009, 2014, 2018, 2023, 2028, 2032, 2037],
            [2042, 2046, 2051, 2056, 2061, 2065, 2070, 2075, 2080, 2084],
            [2089, 2094, 2099, 2104, 2109, 2113, 2118, 2123, 2128, 2133],
            [2138, 2143, 2148, 2153, 2158, 2163, 2168, 2173, 2178, 2183],
            [2188, 2193, 2198, 2203, 2208, 2213, 2218, 2223, 2228, 2234],
            [2239, 2244, 2249, 2254, 2259, 2265, 2270, 2275, 2280, 2286],
            [2291, 2296, 2301, 2307, 2312, 2317, 2323, 2328, 2333, 2339],
            [2344, 2350, 2355, 2360, 2366, 2371, 2377, 2382, 2388, 2393],
            [2399, 2404, 2410, 2415, 2421, 2427, 2432, 2438, 2443, 2449],
            [2455, 2460, 2466, 2472, 2477, 2483, 2489, 2495, 2500, 2506],
            [2512, 2518, 2523, 2529, 2535, 2541, 2547, 2553, 2559, 2564],
            [2570, 2576, 2582, 2588, 2594, 2600, 2606, 2612, 2618, 2624],
            [2630, 2636, 2642, 2649, 2655, 2661, 2667, 2673, 2679, 2685],
            [2692, 2698, 2704, 2710, 2716, 2723, 2729, 2735, 2742, 2748],
            [2754, 2761, 2767, 2773, 2780, 2786, 2793, 2799, 2805, 2812],
            [2818, 2825, 2831, 2838, 2844, 2851, 2858, 2864, 2871, 2877],
            [2884, 2891, 2897, 2904, 2911, 2917, 2924, 2931, 2938, 2944],
            [2951, 2958, 2965, 2972, 2979, 2985, 2992, 2999, 3006, 3013],
            [3020, 3027, 3034, 3041, 3048, 3055, 3062, 3069, 3076, 3083],
            [3090, 3097, 3105, 3112, 3119, 3126, 3133, 3141, 3148, 3155],
            [3162, 3170, 3177, 3184, 3192, 3199, 3206, 3214, 3221, 3228],
            [3236, 3243, 3251, 3258, 3266, 3273, 3281, 3289, 3296, 3304],
            [3311, 3319, 3327, 3334, 3342, 3350, 3357, 3365, 3373, 3381],
            [3388, 3396, 3404, 3412, 3420, 3428, 3436, 3443, 3451, 3459],
            [3467, 3475, 3483, 3491, 3499, 3508, 3516, 3524, 3532, 3540],
            [3548, 3556, 3565, 3573, 3581, 3589, 3597, 3606, 3614, 3622],
            [3631, 3639, 3648, 3656, 3664, 3673, 3681, 3690, 3698, 3707],
            [3715, 3724, 3733, 3741, 3750, 3758, 3767, 3776, 3784, 3793],
            [3802, 3811, 3819, 3828, 3837, 3846, 3855, 3864, 3873, 3882],
            [3890, 3899, 3908, 3917, 3926, 3936, 3945, 3954, 3963, 3972],
            [3981, 3990, 3999, 4009, 4018, 4027, 4036, 4046, 4055, 4064],
            [4074, 4083, 4093, 4102, 4111, 4121, 4130, 4140, 4150, 4159],
            [4169, 4178, 4188, 4198, 4207, 4217, 4227, 4236, 4246, 4256],
            [4266, 4276, 4285, 4295, 4305, 4315, 4325, 4335, 4345, 4355],
            [4365, 4375, 4385, 4395, 4406, 4416, 4426, 4436, 4446, 4457],
            [4467, 4477, 4487, 4498, 4508, 4519, 4529, 4539, 4550, 4560],
            [4571, 4581, 4592, 4603, 4613, 4624, 4634, 4645, 4656, 4667],
            [4677, 4688, 4699, 4710, 4721, 4732, 4742, 4753, 4764, 4775],
            [4786, 4797, 4808, 4819, 4831, 4842, 4853, 4864, 4875, 4887],
            [4898, 4909, 4920, 4932, 4943, 4955, 4966, 4977, 4989, 5000],
            [5012, 5023, 5035, 5047, 5058, 5070, 5082, 5093, 5105, 5117],
            [5129, 5140, 5152, 5164, 5176, 5188, 5200, 5212, 5224, 5236],
            [5248, 5260, 5272, 5284, 5297, 5309, 5321, 5333, 5346, 5358],
            [5370, 5383, 5395, 5408, 5420, 5433, 5445, 5458, 5470, 5483],
            [5495, 5508, 5521, 5534, 5546, 5559, 5572, 5585, 5598, 5610],
            [5623, 5636, 5649, 5662, 5675, 5689, 5702, 5715, 5728, 5741],
            [5754, 5768, 5781, 5794, 5808, 5821, 5834, 5848, 5861, 5875],
            [5888, 5902, 5916, 5929, 5943, 5957, 5970, 5984, 5998, 6012],
            [6026, 6039, 6053, 6067, 6081, 6095, 6109, 6124, 6138, 6152],
            [6166, 6180, 6194, 6209, 6223, 6237, 6252, 6266, 6281, 6295],
            [6310, 6324, 6339, 6353, 6368, 6383, 6397, 6412, 6427, 6442],
            [6457, 6471, 6486, 6501, 6516, 6531, 6546, 6561, 6577, 6592],
            [6607, 6622, 6637, 6653, 6668, 6683, 6699, 6714, 6730, 6745],
            [6761, 6776, 6792, 6808, 6823, 6839, 6855, 6871, 6887, 6902],
            [6918, 6934, 6950, 6966, 6982, 6998, 7015, 7031, 7047, 7063],
            [7079, 7096, 7112, 7129, 7145, 7161, 7178, 7194, 7211, 7228],
            [7244, 7261, 7278, 7295, 7311, 7328, 7345, 7362, 7379, 7396],
            [7413, 7430, 7447, 7464, 7482, 7499, 7516, 7534, 7551, 7568],
            [7586, 7603, 7621, 7638, 7656, 7674, 7691, 7709, 7727, 7745],
            [7762, 7780, 7798, 7816, 7834, 7852, 7870, 7889, 7907, 7925],
            [7943, 7962, 7980, 7998, 8017, 8035, 8054, 8072, 8091, 8110],
            [8128, 8147, 8166, 8185, 8204, 8222, 8241, 8260, 8279, 8299],
            [8318, 8337, 8356, 8375, 8395, 8414, 8433, 8453, 8472, 8492],
            [8511, 8531, 8551, 8570, 8590, 8610, 8630, 8650, 8670, 8690],
            [8710, 8730, 8750, 8770, 8790, 8810, 8831, 8851, 8872, 8892],
            [8913, 8933, 8954, 8974, 8995, 9016, 9036, 9057, 9078, 9099],
            [9120, 9141, 9162, 9183, 9204, 9226, 9247, 9268, 9290, 9311],
            [9333, 9354, 9376, 9397, 9419, 9441, 9462, 9484, 9506, 9528],
            [9550, 9572, 9594, 9616, 9638, 9661, 9683, 9705, 9727, 9750],
            [9772, 9795, 9817, 9840, 9863, 9886, 9908, 9931, 9954, 9977]
        ];
    }

    function antiLogTableSmallDec() internal pure returns (uint8[10][100] memory) {
        return [
            [0, 0, 0, 1, 1, 1, 1, 2, 2, 2],
            [0, 0, 0, 1, 1, 1, 1, 2, 2, 2],
            [0, 0, 0, 1, 1, 1, 1, 2, 2, 2],
            [0, 0, 0, 1, 1, 1, 1, 2, 2, 2],
            [0, 0, 1, 1, 1, 1, 2, 2, 2, 2],
            [0, 0, 1, 1, 1, 1, 2, 2, 2, 2],
            [0, 0, 1, 1, 1, 1, 2, 2, 2, 2],
            [0, 0, 1, 1, 1, 1, 2, 2, 2, 2],
            [0, 0, 1, 1, 1, 1, 2, 2, 2, 3],
            [0, 0, 1, 1, 1, 1, 2, 2, 2, 3],
            [0, 0, 1, 1, 1, 1, 2, 2, 2, 3],
            [0, 0, 1, 1, 1, 2, 2, 2, 2, 3],
            [0, 0, 1, 1, 1, 2, 2, 2, 2, 3],
            [0, 0, 1, 1, 1, 2, 2, 2, 3, 3],
            [0, 0, 1, 1, 1, 2, 2, 2, 3, 3],
            [0, 0, 1, 1, 1, 2, 2, 2, 3, 3],
            [0, 0, 1, 1, 1, 2, 2, 2, 3, 3],
            [0, 0, 1, 1, 1, 2, 2, 2, 3, 3],
            [0, 0, 1, 1, 1, 2, 2, 2, 3, 3],
            [0, 0, 1, 1, 1, 2, 2, 3, 3, 3],
            [0, 0, 1, 1, 1, 2, 2, 3, 3, 3],
            [0, 0, 1, 1, 2, 2, 2, 3, 3, 3],
            [0, 0, 1, 1, 2, 2, 2, 3, 3, 3],
            [0, 0, 1, 1, 2, 2, 2, 3, 3, 4],
            [0, 0, 1, 1, 2, 2, 2, 3, 3, 4],
            [0, 0, 1, 1, 2, 2, 2, 3, 3, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 3, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 3, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 0, 1, 1, 2, 2, 3, 3, 4, 4],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 4, 5],
            [0, 1, 1, 2, 2, 3, 3, 4, 5, 5],
            [0, 1, 1, 2, 2, 3, 4, 4, 5, 5],
            [0, 1, 1, 2, 2, 3, 4, 4, 5, 5],
            [0, 1, 1, 2, 2, 3, 4, 4, 5, 6],
            [0, 1, 1, 2, 3, 3, 4, 4, 5, 6],
            [0, 1, 1, 2, 3, 3, 4, 4, 5, 6],
            [0, 1, 1, 2, 3, 3, 4, 5, 5, 6],
            [0, 1, 1, 2, 3, 3, 4, 5, 5, 6],
            [0, 1, 1, 2, 3, 3, 4, 5, 5, 6],
            [0, 1, 1, 2, 3, 4, 4, 5, 6, 6],
            [0, 1, 1, 2, 3, 4, 4, 5, 6, 6],
            [0, 1, 1, 2, 3, 4, 4, 5, 6, 7],
            [0, 1, 2, 2, 3, 4, 5, 5, 6, 7],
            [0, 1, 2, 2, 3, 4, 5, 5, 6, 7],
            [0, 1, 2, 2, 3, 4, 5, 6, 6, 7],
            [0, 1, 2, 2, 3, 4, 5, 6, 6, 7],
            [0, 1, 2, 2, 3, 4, 5, 6, 7, 7],
            [0, 1, 2, 3, 3, 4, 5, 6, 7, 8],
            [0, 1, 2, 3, 3, 4, 5, 6, 7, 8],
            [0, 1, 2, 3, 4, 4, 5, 6, 7, 8],
            [0, 1, 2, 3, 4, 5, 5, 6, 7, 8],
            [0, 1, 2, 3, 4, 5, 6, 6, 7, 8],
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
            [0, 1, 2, 3, 4, 5, 6, 7, 9, 10],
            [0, 1, 2, 3, 4, 5, 7, 8, 9, 10],
            [0, 1, 2, 3, 4, 6, 7, 8, 9, 10],
            [0, 1, 2, 3, 5, 6, 7, 8, 9, 10],
            [0, 1, 2, 4, 5, 6, 7, 8, 9, 11],
            [0, 1, 2, 4, 5, 6, 7, 8, 10, 11],
            [0, 1, 2, 4, 5, 6, 7, 9, 10, 11],
            [0, 1, 3, 4, 5, 6, 8, 9, 10, 11],
            [0, 1, 3, 4, 5, 6, 8, 9, 10, 12],
            [0, 1, 3, 4, 5, 7, 8, 9, 10, 12],
            [0, 1, 3, 4, 5, 7, 8, 9, 11, 12],
            [0, 1, 3, 4, 5, 7, 8, 10, 11, 12],
            [0, 1, 3, 4, 6, 7, 8, 10, 11, 13],
            [0, 1, 3, 4, 6, 7, 9, 10, 11, 13],
            [0, 1, 3, 4, 6, 7, 9, 10, 12, 13],
            [0, 2, 3, 5, 6, 8, 9, 11, 12, 14],
            [0, 2, 3, 5, 6, 8, 9, 11, 12, 14],
            [0, 2, 3, 5, 6, 8, 9, 11, 13, 14],
            [0, 2, 3, 5, 6, 8, 10, 11, 13, 15],
            [0, 2, 3, 5, 7, 8, 10, 12, 13, 15],
            [0, 2, 3, 5, 7, 8, 10, 12, 13, 15],
            [0, 2, 3, 5, 7, 9, 10, 12, 14, 16],
            [0, 2, 4, 5, 7, 9, 11, 12, 14, 16],
            [0, 2, 4, 5, 7, 9, 11, 13, 14, 16],
            [0, 2, 4, 6, 7, 9, 11, 13, 15, 17],
            [0, 2, 4, 6, 8, 9, 11, 13, 15, 17],
            [0, 2, 4, 6, 8, 10, 12, 14, 15, 17],
            [0, 2, 4, 6, 8, 10, 12, 14, 16, 18],
            [0, 2, 4, 6, 8, 10, 12, 14, 16, 18],
            [0, 2, 4, 6, 8, 10, 12, 15, 17, 19],
            [0, 2, 4, 6, 8, 11, 13, 15, 17, 19],
            [0, 2, 4, 7, 9, 11, 13, 15, 17, 20],
            [0, 2, 4, 7, 9, 11, 13, 16, 18, 20],
            [0, 2, 5, 7, 9, 11, 14, 16, 18, 20]
        ];
    }
}

/// @dev https://icap.org.pk/files/per/students/exam/notices/log-table.pdf
bytes constant LOG_TABLE =
// | 10 | 0000 | 0043 | 0086 | 0128 | 0170 | 0212' | 0253' | 0294' | 0334' | 0374' |
    hex"0000" hex"002b" hex"0056" hex"0080" hex"00aa" hex"80d4" hex"80fd" hex"8126" hex"814e" hex"8176"
    // | 11 | 0414 | 0453 | 0492 | 0531 | 0569 | 0607' | 0645' | 0682' | 0719' | 0755' |
    hex"019e" hex"01c5" hex"01ec" hex"0213" hex"0239" hex"825f" hex"8285" hex"82aa" hex"82cf" hex"82f3";

bytes constant LOG_TABLE_SMALL =
// | 10 | 0 | 4 | 9 | 13 | 17 | 21 | 26 | 30 | 34 | 38 |
    hex"00" hex"04" hex"09" hex"0d" hex"11" hex"15" hex"1a" hex"1e" hex"22" hex"26"
    // | 11 | 0 | 4 | 8 | 12 | 15 | 19 | 23 | 27 | 31 | 35 |
    hex"00" hex"04" hex"08" hex"0c" hex"0f" hex"13" hex"17" hex"1b" hex"1f" hex"23";

bytes constant LOG_TABLE_SMALL_ALT =
// | 10 | 0 | 4 | 8 | 12 | 16 | 20 | 24 | 28 | 32 | 37 |
    hex"00" hex"04" hex"08" hex"0c" hex"10" hex"14" hex"18" hex"1c" hex"20" hex"25"
    // | 11 | 0 | 4 | 7 | 11 | 15 | 19 | 22 | 26 | 30 | 33 |
    hex"00" hex"04" hex"07" hex"0b" hex"0f" hex"13" hex"16" hex"1a" hex"1e" hex"21";
