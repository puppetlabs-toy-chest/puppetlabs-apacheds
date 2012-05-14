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
  $version = '2.0.0-M6'
) {

  class { 'java': distribution => 'jre' }

  package { 'apacheds':
    ensure  => $version,
    require => Class['java'],
  }

  Exec { logoutput => on_failure }

  # Config file needs to me managed in some for or another to be able to add
  # our partition and turn on SSL.  Production module will use java_ks for
  # certificates and a more thoroughly templatized config...unless it get a
  # little crazy and write something to generalize the management of xml files...
  file { 'server_config':
    path    => "/var/lib/apacheds-${version}/default/conf/server.xml",
    ensure  => present,
    content => template("${module_name}/server_xml.erb"),
    mode    => '0644',
    owner   => 'apacheds',
    group   => 'apacheds',
    notify  => Service['apacheds'],
    require => Package['apacheds'],
  }

  # The service exits as up before the LDAP backend it full up.  Giving it a
  # little extra time to come up...Yet another reason for a type to do the LDIF
  # modifications, clean retries.
  service { 'apacheds':
    name    => "apacheds-${version}-default",
    ensure  => running,
    enable  => true,
    restart => "/etc/init.d/apacheds-${version}-default restart && sleep 5",
    require => Package['apacheds'],
  }

  # All our templates that need to be loaded into our new LDAP server.  None
  # are actually currently "templates"...The template function just works best
  # when interacting with Exec resources.
  $rootpw_ldif = template("${module_name}/rootpw_ldif.erb")
  $schema_ldif = template("${module_name}/schemas_ldif.erb")
  $pl_context_ldif = template("${module_name}/pl_context_ldif.erb")
  $ou_ldif = template("${module_name}/ou_ldif.erb")
  $entries_ldif = template("${module_name}/entries_ldif.erb")
  $initial_subentry_ldif = template("${module_name}/initial_subentry_ldif.erb")
  $self_access_ldif = template("${module_name}/self_access_ldif.erb")
  $dir_managers_ldif = template("${module_name}/dir_managers_ldif.erb")

  # Now to change the default password.  Have to wait a little while for the
  # password to expire from the cache so we can do the later operations.
  exec { 'update password':
    command => "echo '${rootpw_ldif}' | ldapmodify -ZZ -D uid=admin,ou=system -H ldap://${server}:${port} -x -w secret && sleep 5",
    onlyif  => "ldapsearch -ZZ -D uid=admin,ou=system -LLL -H ldap://${server}:${port} -x -w secret -b ou=system ou=system",
    path    => [ '/bin', '/usr/bin' ],
    require => Service['apacheds'],
  }

  # Turn on specific schemas for doing posix account management.
  exec { 'turn on schemas':
    command => "echo '${schema_ldif}' | ldapmodify -ZZ -D uid=admin,ou=system -H ldap://${server}:${port} -x -w ${rootpw}",
    onlyif  => "ldapsearch -ZZ -LLL -D uid=admin,ou=system -H ldap://${server}:${port} -x -w ${rootpw} -b ou=schema cn=nis m-disabled | grep TRUE",
    path    => [ '/bin', '/usr/bin' ],
    require => Exec['update password'],
  }

  # Adds the base context for our dc=puppetlabs,dc=net parition.
  exec { 'add context':
    command => "echo '${pl_context_ldif}' | ldapadd -ZZ -D uid=admin,ou=system -H ldap://${server}:${port} -x -w ${rootpw}",
    onlyif  => "test `ldapsearch -ZZ -D uid=admin,ou=system -LLL -H ldap://${server}:${port} -x -w ${rootpw} -b dc=puppetlabs,dc=net '(ObjectClass=*)' dc=puppetlabs,dc=net | wc -l` = 0",
    path    => [ '/bin', '/usr/bin' ],
    require => Exec['update password'],
  }

  # Add a set of precanned organizational units that work well for us.
  exec { 'add ou':
    command => "echo '${ou_ldif}' | ldapadd -ZZ -D uid=admin,ou=system -H ldap://${server}:${port} -x -w ${rootpw}",
    unless  => "test `ldapsearch -D uid=admin,ou=system -ZZ -H ldap://${server}:${port} -w ${rootpw} -x -b dc=puppetlabs,dc=net -LLL '(|(ou=people)(ou=group)(ou=autofs))' ou | grep ou: | wc -l` = 3",
    path    => [ '/bin', '/usr/bin' ],
    require => Exec[[ 'add context', 'turn on schemas' ] ],
  }

  # Adds a few default entries that people can use at templates for creating
  # new users, groups, or automounts.
  exec { 'add entries':
    command => "echo '${entries_ldif}' | ldapadd -ZZ -D uid=admin,ou=system -H ldap://${server}:${port} -x -w ${rootpw}",
    unless  => "test `ldapsearch -D uid=admin,ou=system -ZZ -H ldap://${server}:${port} -w ${rootpw} -x -b dc=puppetlabs,dc=net -LLL uid=zero uid | grep uid: | wc -l` = 1",
    path    => [ '/bin', '/usr/bin' ],
    require => Exec[ [ 'add ou', 'turn on schemas' ] ],
  }

  exec { 'intial subentry and aci':
    command => "echo '${initial_subentry_ldif}' | ldapadd -ZZ -D uid=admin,ou=system -H ldap://${server}:${port} -x -w ${rootpw}",
    unless  => "ldapsearch -ZZ -H ldap://${server}:${port} -D uid=admin,ou=system -w ${rootpw} -x -b dc=puppetlabs,dc=net -E subentries=true -LLL cn=puppetlabsACISubentry | grep 'cn: puppetlabsACISubentry'",
    path    => [ '/bin', '/usr/bin' ],
    require => Exec['add context'],
  }

  exec { 'self access':
    command => "echo '${self_access_ldif}' | ldapadd -ZZ -D uid=admin,ou=system -H ldap://${server}:${port} -x -w ${rootpw}",
    unless  => "ldapsearch -ZZ -H ldap://${server}:${port} -D uid=admin,ou=system -w ${rootpw} -x -b dc=puppetlabs,dc=net -E subentries=true -LLL cn=puppetlabsACISubentry prescriptiveACI | grep allowSelfAccessAndModification",
    path    => [ '/bin', '/usr/bin' ],
    require => Exec['intial subentry and aci'],
  }

  exec { 'directory managers':
    command => "echo '${dir_managers_ldif}' | ldapadd -ZZ -D uid=admin,ou=system -H ldap://${server}:${port} -x -w ${rootpw}",
    unless  => "ldapsearch -ZZ -H ldap://${server}:${port} -D uid=admin,ou=system -w ${rootpw} -x -b dc=puppetlabs,dc=net -E subentries=true -LLL cn=puppetlabsACISubentry prescriptiveACI | grep directoryManagerFullAccessACI",
    path    => [ '/bin', '/usr/bin' ],
    require => Exec['intial subentry and aci'],
  }
}
