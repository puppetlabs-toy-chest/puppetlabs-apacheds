# == Class: apacheds
#
# Full description of class apacheds here.
#
# === Parameters
#
# Document parameters here.
#
# [*sample_parameter*]
#   Explanation of what this parameter affects and what it defaults to.
#   e.g. "Specify one or more upstream ntp servers as an array."
#
# === Variables
#
# Here you should define a list of variables that this module would require.
#
# [*sample_variable*]
#   Explanation of how this variable affects the funtion of this class and if it
#   has a default. e.g. "The parameter enc_ntp_servers must be set by the
#   External Node Classifier as a comma separated list of hostnames." (Note,
#   global variables should not be used in preference to class parameters  as of
#   Puppet 2.6.)
#
# === Examples
#
#  class { apacheds:
#    servers => [ 'pool.ntp.org', 'ntp.local.company.com' ]
#  }
#
# === Authors
#
# Author Name <author@domain.com>
#
# === Copyright
#
# Copyright 2011 Your name here, unless otherwise noted.
#
class apacheds(
  $rootpw = 'foobar',
  $server = 'ldap-module.vm.vmware',
  $port   = '10389',
) {

  class { 'java': distribution => 'jre' }

  package { 'apacheds':
    ensure  => '1.5.7',
    require => Class['java'],
  }

  # Config file needs to me managed in some for or another to be able to add
  # our partition and turn on SSL.  Production module will use java_ks for
  # certificates and a more thoroughly templatized config...unless it get a
  # little crazy and write something to generalize the management of xml files...
  file { 'server_config':
    path    => '/var/lib/apacheds-1.5.7/default/conf/server.xml',
    ensure  => present,
    content => template("${module_name}/server_xml.erb"),
    mode    => '0644',
    owner   => 'apacheds',
    group   => 'apacheds',
    notify  => Service['apacheds-1.5.7-default'],
    require => Package['apacheds'],
  }

  service { 'apacheds-1.5.7-default':
    ensure     => running,
    enable     => true,
    hasrestart => true,
    require    => Package['apacheds'],
  }

  $rootpw_ldif = template("${module_name}/rootpw_ldif.erb")
  $schema_ldif = template("${module_name}/schemas_ldif.erb")
  $pl_context_ldif = template("${module_name}/pl_context_ldif.erb")

  # Now to change the default password.
  exec { 'update password':
    command => "echo '${rootpw_ldif}' | ldapmodify -ZZ -D uid=admin,ou=system -H ldap://${server}:${port} -x -w secret",
    onlyif  => "ldapsearch -ZZ -D uid=admin,ou=system -LLL -H ldap://${server}:${port} -x -w secret -b ou=system ou=system",
    path    => [ '/bin', '/usr/bin' ],
    require => Package['apacheds'],
  }

  # Turn on specific schemas
  exec { 'turn on schemas':
    command => "echo '${schema_ldif}' | ldapmodify -ZZ -D uid=admin,ou=system -H ldap://${server}:${port} -x -w ${rootpw}",
    onlyif  => "ldapsearch -ZZ -LLL -H ldap://${server}:${port} -x -b ou=schema cn=nis m-disabled | grep TRUE",
    path    => [ '/bin', '/usr/bin' ],
    require => Exec['update password'],
  }

  exec { 'add context':
    command => "echo '${pl_context_ldif}' | ldapadd -ZZ -D uid=admin,ou=system -H ldap://${server}:${port} -x -w ${rootpw}",
    unless  => "ldapsearch -ZZ -D uid=admin,ou=system -LLL -H ldap://${server}:${port} -x -w ${rootpw} -b dc=puppetlabs,dc=net dc=puppetlabs,dc=net",
    path    => [ '/bin', '/usr/bin' ],
    require => Exec['update password'],
  }
}
