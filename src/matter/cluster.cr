# Cluster framework and every server cluster implementation.
module Matter
  module Cluster
    # Fallback logger for cluster files that do not define their own `Log`.
    Log = ::Log.for("matter.cluster")
  end
end

require "./cluster/cluster"
require "./cluster/label_struct"

require "./cluster/color_control_utils"

require "./cluster/access_control_cluster"
require "./cluster/administrator_commissioning_cluster"
require "./cluster/basic_information_cluster"
require "./cluster/boolean_state_cluster"
require "./cluster/bridged_device_basic_information_cluster"
require "./cluster/carbon_dioxide_concentration_measurement_cluster"
require "./cluster/color_control_cluster"
require "./cluster/descriptor_cluster"
require "./cluster/diagnostic_logs_cluster"
require "./cluster/door_lock_cluster"
require "./cluster/ethernet_network_diagnostics_cluster"
require "./cluster/fan_control_cluster"
require "./cluster/fixed_label_cluster"
require "./cluster/general_commissioning_cluster"
require "./cluster/general_diagnostics_cluster"
require "./cluster/group_key_management_cluster"
require "./cluster/groups_cluster"
require "./cluster/icd_management_cluster"
require "./cluster/identify_cluster"
require "./cluster/illuminance_measurement_cluster"
require "./cluster/level_control_cluster"
require "./cluster/network_commissioning_cluster"
require "./cluster/occupancy_sensing_cluster"
require "./cluster/on_off_cluster"
require "./cluster/operational_credentials_cluster"
require "./cluster/ota_requestor_cluster"
require "./cluster/power_source_cluster"
require "./cluster/pressure_measurement_cluster"
require "./cluster/relative_humidity_measurement_cluster"
require "./cluster/scenes_management_cluster"
require "./cluster/temperature_measurement_cluster"
require "./cluster/thermostat_cluster"
require "./cluster/time_format_localization_cluster"
require "./cluster/user_label_cluster"
require "./cluster/window_covering_cluster"
