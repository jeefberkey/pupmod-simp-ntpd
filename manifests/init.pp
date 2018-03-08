# Set up ntpd in either standalone or server mode
#
# @see ntp.conf(5)
#
# @param servers
#   An array of servers or a Hash of server/option pairs providing details
#   for the NTP servers that this system should synchronize with
#
#   * **Example**
#
#     ```
#     servers => {
#       'time.local.net' => ['iburst','minpoll 4', 'prefer'],
#       # This one will just use $default_options
#       'time.other.net' => []
#     }
#     ```
#
# @param stratum
#   The stratum for this system
#
#   * This only comes into play if no external servers are defined and the
#     stratum has to be fudged
#
# @param logconfig
#   A list of options for refining the system log output
#
# @param broadcastdelay
#   Default calibration delay
#
# @param default_options
#   The default options that will be added to all servers
#
#   * Set to an empty array to disable
#
# @param disable_monitor
#   Disable the monitoring facility to prevent amplification attacks using
#   ``ntpdc monlist`` command when default restrict does not include the
#   ``noquery`` flag
#
#   * See CVE-2013-5211 for details
#
# @param manage_step_tickers Manage /etc/ntp/step-tickers
#
# @param auditd
#   Enable auditd monitoring of the ntp configuration files
#
#   * This probably isn't needed in most cases since Puppet controls these
#     files, but some systems require it
#
# @param package_ensure `ensure` parameter for the `ntp` package
#
# @author https://github.com/simp/pupmod-simp-ntpd/graphs/contributors
#
class ntpd (
  Ntpd::Servers $servers             = simplib::lookup('simp_options::ntpd::servers', { 'default_value' => {} }),
  Integer[0]    $stratum             = 2,
  Array[String] $logconfig           = ['=syncall','+clockall'],
  Numeric       $broadcastdelay      = 0.004,
  Array[String] $default_options     = ['minpoll 4','maxpoll 4','iburst'],
  Boolean       $disable_monitor     = true,
  Boolean       $manage_step_tickers = true,
  Boolean       $auditd              = simplib::lookup('simp_options::auditd', { 'default_value' => false}),
  String        $package_ensure      = simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' }),
){

  concat { '/etc/ntp.conf':
    owner          => 'root',
    group          => 'ntp',
    mode           => '0600',
    ensure_newline => true,
    warn           => true,
    require        => Package['ntp'],
    notify         => Service['ntpd']
  }

  concat::fragment { 'main_ntp_configuration':
    target  => '/etc/ntp.conf',
    content => template("${module_name}/ntp.conf.erb"),
    order   => 0,
  }

  file { '/etc/ntp':
    ensure => directory,
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    notify => Service['ntpd']
  }

  file { '/etc/ntp/keys':
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => "\n",
    notify  => Service['ntpd']
  }

  file { '/var/lib/ntp':
    ensure => 'directory',
    owner  => 'ntp',
    group  => 'ntp',
    mode   => '0750',
    notify => Service['ntpd']
  }

  $_sysconfig_content = @(EOF)
    OPTIONS="-A -u ntp:ntp -p /var/run/ntpd.pid"
    SYNC_HWCLOCK=yes
    | EOF
  file { '/etc/sysconfig/ntpd':
    ensure  => 'file',
    owner   => 'root',
    group   => 'root',
    mode    => '0640',
    content => $_sysconfig_content,
    notify  => Service['ntpd']
  }

  if $servers =~ Array {
    $_servers = $servers
  }
  else {
    $_servers = $servers.keys
  }
  file { '/etc/ntp/step-tickers':
    ensure  => 'file',
    content => epp("${module_name}/step-tickers.epp", { 'ntp_servers' => $_servers }),
    notify  => Service['ntpd']
  }

  group { 'ntp':
    ensure    => 'present',
    allowdupe => false,
    gid       => 38,
    before    => Service['ntpd']
  }

  user { 'ntp':
    ensure     => 'present',
    allowdupe  => false,
    gid        => 'ntp',
    home       => '/etc/ntp',
    membership => 'inclusive',
    shell      => '/sbin/nologin',
    uid        => 38,
    before     => Service['ntpd']
  }

  package { 'ntp':
    ensure => $package_ensure,
    before => User['ntp']
  }

  service { 'ntpd':
    ensure     => running,
    enable     => true,
    hasrestart => true,
    hasstatus  => true,
    require    => Package['ntp']
  }

  if $auditd {
    include '::auditd'

    $_audit_rule = @(EOF)
      -w /etc/ntp.conf -p wa -k CFG_ntp
      -w /etc/ntp/keys -p wa -k CFG_ntp
      | EOF
    # Add the audit rules
    auditd::rule { 'ntp':
      content => $_audit_rule,
      require => [
        Concat['/etc/ntp.conf'],
        File['/etc/ntp/keys']
      ]
    }
  }

}
