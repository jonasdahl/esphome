package reg

import (
	"encoding/csv"
	"strconv"
	"math"
	"strings"
	"list"
	"regexp"
)

_input: string
let decoded = csv.Decode(_input)

let keys = decoded[0]

let records = [...{
	Register:    string        // "650"
	Byte:        null | string // "HwR"
	Bit:         null | string // "0"
	Selected?:   null | "x"
	Description: string // "HW output: Compressor on/off"
	Type:        "BOOL" | "U16" | "S16" | "U8"
	Values:      null | string // "1=On, 0=Off"
	Unit:        null | string // "0.1Kw"
	Min:         null | string // "-50"
	Max:         null | string // "250"
	"R/W":       "R/W" | "R"
}] & [
	for record in list.Drop(decoded, 1) {
		for i, cell in record {
			if cell == "" {
				(keys[i]): null
			}
			if cell != "" {
				(keys[i]): cell
			}
		}
	},
]

let converted = [
	for record in records if record.Selected == "x" {
		address: strconv.Atoi(record.Register)
		register_type: {"R": "read", "R/W": "holding"}[record["R/W"]]

		_kind: string
		if record.Type == "S16" {
			value_type: "S_WORD"
		}

		if record.Type == "BOOL" {
			_kind: "binary_sensor"
		}

		// if record.Type != "BOOL" && record.Values != null {
		// 	_kind: "text_sensor"

		// 	let cases = strings.Join([for case in strings.Split(record.Values, ",") {
		// 		let kv = strings.Split(case, "=")
		// 		#"case \#(strings.TrimSpace(kv[0])): return std::string("\#(kv[1])");"#
		// 	}], "\n")

		// 	raw_encode: "HEXBYTES"
		// 	lambda:     """
		// 		uint16_t value = modbus_controller::word_from_hex_str(x, 0);
		// 		switch (value) {
		// 		\(cases)
		// 		default: return std::string("Unknown");
		// 		}
		// 		return x;
		// 		"""
		// }

		if record.Type =~ "[SU]16" {
			if register_type == "read" {
				_kind:             "sensor"
				state_class:       "measurement"
				accuracy_decimals: 1
			}

			if register_type == "holding" {
				_kind:           "number"
				entity_category: "config"
				if record.Unit != null {
					if record.Unit =~ "0.." {
						let num = strconv.ParseFloat(regexp.Find("0..", record.Unit), 64)
						multiply: 1 / num
						step:     num
					}
				}
			}
		}

		name: record.Description

		if record.Bit != null {
			bitmask: math.Exp2(strconv.ParseInt(record.Bit, 10, 0))
		}

		_filters: {}
		if len(_filters) > 0 {filters: [for key, value in _filters {{(key): value}}]}

		if record.Max != null && record.Min != null && _kind != "number" {
			_filters: clamp: {
				min_value:           record.Min
				max_value:           record.Max
				ignore_out_of_range: true
			}
		}

		if record.Unit != null {
			if _kind != "number" && record.Unit =~ "0.." {
				_filters: multiply: strconv.ParseFloat(regexp.Find("0..", record.Unit), 64)
			}

			if strings.HasSuffix(record.Unit, "°C") {
				unit_of_measurement: "°C"
				device_class:        "temperature"
			}

			if strings.HasSuffix(record.Unit, "Bar") {
				unit_of_measurement: "Bar"
				device_class:        "pressure"
			}

			if strings.HasSuffix(record.Unit, "Kw") {
				unit_of_measurement: "kW"
				device_class:        "energy"
			}

			if strings.HasSuffix(record.Unit, "A") {
				unit_of_measurement: "A"
				device_class:        "current"
			}

			if strings.HasSuffix(record.Unit, "%") {
				unit_of_measurement: "%"
			}
		}

	},
]

{
	esphome: name: "ctc-ecozenith-i250"
	esp32: {
		board: "lolin_s2_mini"
		framework: type: "esp-idf"
	}
	logger: {}
	api: password: ""
	ota: [{
		platform: "esphome"
		password: ""
	}]

	wifi: {
		ssid:     "!secret wifi_ssid"
		password: "!secret wifi_password"

		ap: {
			ssid:     "Ctc-Ecozenith-I250"
			password: "uJIlEWvInhDB"
		}

	}

	captive_portal: {}

	uart: {
		id:        "mod_bus"
		tx_pin:    17
		rx_pin:    16
		baud_rate: 9600
		parity:    "EVEN"
		stop_bits: 1
	}

	modbus: {
		flow_control_pin: 18
		id:               "modbus1"
	}

	modbus_controller: [{
		id:             "ctc"
		address:        0x1
		modbus_id:      "modbus1"
		setup_priority: -10
	}]

	#modbus: {
		platform:             "modbus_controller"
		modbus_controller_id: "ctc"
		address!:             int
		register_type!:       "read" | "holding" | "coil"
		...
	}

	sensor: [
		for register in converted if register._kind == "sensor" {
			#modbus & register
		},
	]
	binary_sensor: [
		for register in converted if register._kind == "binary_sensor" {
			#modbus & register
		},
	]
	// text_sensor: [
	// 	for register in converted if register._kind == "text_sensor" {
	// 		#modbus & register
	// 	},
	// ]
	number: [
		for register in converted if register._kind == "number" {
			#modbus & register
		},
	]
}
