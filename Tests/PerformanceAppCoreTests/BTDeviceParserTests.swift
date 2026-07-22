import Testing
import Foundation
@testable import PerformanceAppCore

@Suite("BTDeviceParser")
struct BTDeviceParserTests {

    private var sampleData: Data {
        let json = """
        {
          "SPBluetoothDataType": [
            {
              "device_connected": [
                {
                  "AirPods Pro": {
                    "device_address": "00-11-22-33-44-55",
                    "device_batteryLevelLeft": "50 %",
                    "device_batteryLevelRight": "100 %",
                    "device_batteryLevelCase": "20 %"
                  }
                },
                {
                  "Magic Keyboard": {
                    "device_address": "AA-BB-CC-DD-EE-FF",
                    "device_batteryLevel": "75%"
                  }
                }
              ],
              "device_not_connected": [
                {
                  "Old Mouse": {
                    "device_address": "11-22-33-44-55-66",
                    "device_batteryLevel": "10 %"
                  }
                }
              ]
            }
          ]
        }
        """
        return json.data(using: .utf8)!
    }

    @Test func parsesConnectedDevices() {
        let parsed = BTDeviceParser.parse(sampleData)
        #expect(parsed != nil)
        
        let airPods = parsed?["00:11:22:33:44:55"]
        #expect(airPods != nil)
        #expect(airPods?.left == 50)
        #expect(airPods?.right == 100)
        #expect(airPods?.caseLevel == 20)
        #expect(airPods?.main == nil)

        let keyboard = parsed?["aa:bb:cc:dd:ee:ff"]
        #expect(keyboard != nil)
        #expect(keyboard?.main == 75)
    }

    @Test func parsesDisconnectedDevices() {
        let parsed = BTDeviceParser.parse(sampleData)
        let mouse = parsed?["11:22:33:44:55:66"]
        #expect(mouse != nil)
        #expect(mouse?.main == 10)
    }

    @Test func returnsNilOnInvalidData() {
        let badData = "Not JSON".data(using: .utf8)!
        let parsed = BTDeviceParser.parse(badData)
        #expect(parsed == nil)
    }

    @Test func handlesMissingBatteryData() {
        let json = """
        {
          "SPBluetoothDataType": [
            {
              "device_connected": [
                {
                  "Mystery Device": {
                    "device_address": "FF-FF-FF-FF-FF-FF"
                  }
                }
              ]
            }
          ]
        }
        """
        let parsed = BTDeviceParser.parse(json.data(using: .utf8)!)
        let mystery = parsed?["ff:ff:ff:ff:ff:ff"]
        #expect(mystery != nil)
        #expect(mystery?.main == nil)
        #expect(mystery?.left == nil)
    }
}
