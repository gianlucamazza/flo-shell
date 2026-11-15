harness = static_library('harness', 'harness.c')

test('unit', executable('test_unit', 'test_unit.c', link_with: common))

integration = executable('test_integration', 'test_integration.c', link_with: harness)

# Keep in sync with the table at the end of test_integration.c
# (test_integration --list prints it).
foreach name : [
  'boost_first_touch', 'boost_streaming', 'boost_timestamps', 'boost_sigterm',
  'boost_command', 'boost_uclamp', 'crash_restore', 'kill_recovery',
  'device_hotplug', 'cpu_offline', 'idle',
  'freezer_grace', 'freezer_allowlist', 'freezer_inhibit', 'freezer_fail_open',
  'freezer_controls', 'freezer_exit', 'freezer_new_app',
  'proto_negative', 'many_clients', 'socket', 'socket_activation', 'floctl', 'config',
]
  test(name, integration,
    args: [sessiond, floctl, name],
    timeout: 120,
    suite: 'integration',
  )
endforeach
