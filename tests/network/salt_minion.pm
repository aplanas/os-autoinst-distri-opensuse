# SUSE's openQA tests
#
# Copyright © 2016-2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Test Salt stack on two machines. This machine is running
#  salt-minion only and here we test the end result of master operations.
# Maintainer: Pavel Dostal <pdostal@suse.cz>

use base "consoletest";
use strict;
use warnings;
use testapi;
use lockapi;
use mm_network 'setup_static_mm_network';
use utils qw(zypper_call systemctl);

sub run {
    select_console 'root-console';
    my $hostname = get_var('HOSTNAME');

    # Wait until the master is ready
    mutex_wait 'SALT_MASTER_READY';

    # Install the salt minion
    zypper_call('in salt-minion');

    # Set the right address of the salt master
    assert_script_run('sed -i -e "s/#master: .*/master: 10.0.2.101/" /etc/salt/minion');
    assert_script_run('sed -i -e "s/#ipv6: .*/ipv6: False/" /etc/salt/minion');
    assert_script_run("grep 'master:\\\|ipv6:' /etc/salt/minion");
    assert_script_run "echo '$hostname' > /etc/salt/minion_id";

    # Enable and start the salt-minion
    systemctl 'enable salt-minion';
    systemctl 'start salt-minion';
    systemctl 'status salt-minion';

    # before accepting the key, wait until the minion is fully started (systemd might be not reliable)
    barrier_wait 'SALT_MINIONS_READY';

    # Wait for the keys to be accepted
    mutex_wait 'SALT_KEYS_ACCEPTED';
    assert_script_run('salt-call -l debug test.ping', timeout => 360);

    # Check that the command executed from the master was successfully done
    mutex_wait 'SALT_TOUCH';
    assert_script_run("ls /tmp/salt_touch | grep salt_touch");

    # Check that the package installed from the master is present
    mutex_wait 'SALT_STATES_PKG';
    assert_script_run("which pidstat");

    # Check that the user and it's group created from the master are present
    mutex_wait 'SALT_STATES_USER';
    assert_script_run("sudo -iu salttestuser whoami");
    assert_script_run("sudo -iu salttestuser pwd | grep /home/salttestuser");
    assert_script_run("sudo -iu salttestuser groups | grep salttestgroup");

    # Check that the sysctl value set from the master has right value
    mutex_wait 'SALT_STATES_SYSCTL';
    assert_script_run("sysctl -a | grep 'net.ipv4.ip_forward = 1'");

    # Stop the minion at the end
    barrier_wait 'SALT_FINISHED';
    systemctl 'stop salt-minion';
}

1;
