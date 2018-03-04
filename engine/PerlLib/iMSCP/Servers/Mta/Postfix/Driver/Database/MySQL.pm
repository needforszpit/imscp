=head1 NAME

 iMSCP::Servers::Mta::Postfix::Driver::Database::MySQL - i-MSCP MySQL database driver for Postfix

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2018 Laurent Declercq <l.declercq@nuxwin.com>
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

package iMSCP::Servers::Mta::Postfix::Driver::Database::MySQL;

use strict;
use warnings;
use autouse 'iMSCP::Crypt' => qw/ ALNUM randomStr /;
use autouse 'iMSCP::Rights' => qw/ setRights /;
use Class::Autouse qw/ :nostat iMSCP::Database iMSCP::Dir iMSCP::Servers::Sqld /;
use iMSCP::File;
use iMSCP::Boolean;
use iMSCP::Umask;
use parent 'iMSCP::Servers::Mta::Postfix::Driver::Database::Abstract';

=head1 DESCRIPTION

 i-MSCP MySQL database driver for Postfix.
 
 See http://www.postfix.org/MYSQL_README.html
 See http://www.postfix.org/mysql_table.5.html
 See http://www.postfix.org/proxymap.8.html

=head1 PUBLIC METHODS

=over 4

=item install( )

 See iMSCP::Servers::Mta::Postfix::Driver::Database::Abstract::install()

=cut

sub install
{
    my ( $self ) = @_;

    $self->_setupDatabases();
}

=item uninstall( )

 See iMSCP::Servers::Mta::Postfix::Driver::Database::Abstract::uninstall()

=cut

sub uninstall
{
    my ( $self ) = @_;

    iMSCP::Dir->new( dirname => $self->{'mta'}->{'config'}->{'MTA_DB_DIR'} )->remove();
}

=item setEnginePermissions( )

 See iMSCP::Servers::Mta::Postfix::Driver::Database::Abstract::setEnginePermissions()

=cut

sub setEnginePermissions
{
    my ( $self ) = @_;

    setRights( $self->{'mta'}->{'config'}->{'MTA_DB_DIR'},
        {
            user      => $::imscpConfig{'ROOT_USER'},
            group     => $::imscpConfig{'ROOT_GROUP'},
            dirmode   => '0750',
            filemode  => '0640',
            recursive => TRUE
        }
    );
}

=item getDbType( )

 See iMSCP::Server::Mta::Posfix::Driver::Database::Abstract::getDbType()

=cut

sub getDbType
{
    my ( $self ) = @_;

    'mysql';
}

=back

=head1 PRIVATE METHODS

=over 4

=item _setupDatabases( )

 Setup default databases

 Return void, die on failure

=cut

sub _setupDatabases
{
    my ( $self ) = @_;

    # Create SQL user

    my $sqlUser = 'imscp_postfix_user';
    my $sqlUserHost = ::setupGetQuestion( 'DATABASE_USER_HOST' );
    my $sqlUserPassword = randomStr( 16, ALNUM );
    my $sqlServer = iMSCP::Servers::Sqld->factory();

    for my $host ( $sqlUserHost, $::imscpOldConfig{'DATABASE_USER_HOST'} ) {
        next unless length $host;
        $sqlServer->dropUser( 'imscp_postfix_user', $host );
    }

    $sqlServer->createUser( $sqlUser, $sqlUserHost, $sqlUserPassword );

    my $dbh = iMSCP::Database->getInstance();
    my $qDbName = $dbh->quote_identifier( ::setupGetQuestion( 'DATABASE_NAME' ));
    $dbh->do( "GRANT SELECT ON $qDbName.mail_users TO ?\@?", undef, $sqlUser, $sqlUserHost );

    # Create MySQL sources

    {
        # Change the umask once. The change will be effective for the full
        # enclosing block.
        local $UMASK = 0027;

        # Make sure to start with a clean directory by re-creating it from scratch
        iMSCP::Dir->new( dirname => $self->{'mta'}->{'config'}->{'MTA_DB_DIR'} )->remove()->make();

        my $dbname = ::setupGetQuestion( 'DATABASE_NAME' );
        my $dbHost = ::setupGetQuestion( 'DATABASE_HOST' );
        my $dbDir = $self->{'mta'}->{'config'}->{'MTA_DB_DIR'};

        # virtual_alias_maps.cf
        $self->{'mta'}->buildConfFile( iMSCP::File->new( filename => "$dbDir/virtual_alias_maps.cf" )->set( <<"EOF" ));
user = $sqlUser
password = $sqlUserHost
hosts = $dbHost
dbname = $dbname
query =
EOF
        # virtual_mailbox_domains.cf
        $self->{'mta'}->buildConfFile( iMSCP::File->new( filename => "$dbDir/virtual_mailbox_domains.cf" )->set( <<"EOF" ));
user = $sqlUser
password = $sqlUserHost
hosts = $dbHost
dbname = $dbname
query  =
EOF
        # virtual_mailbox_maps.cf
        $self->{'mta'}->buildConfFile( iMSCP::File->new( filename => "$dbDir/virtual_alias_maps.cf" )->set( <<"EOF" ));
mysql_virtual_alias_domain_mailbox_maps.cf:
user = $sqlUser
password = $sqlUserHost
hosts = $dbHost
dbname = $dbname
query = 
EOF
        # relay_domains.cf
        $self->{'mta'}->buildConfFile( iMSCP::File->new( filename => "$dbDir/virtual_alias_maps.cf" )->set( <<"EOF" ));
user = $sqlUser
password = $sqlUserHost
hosts = $dbHost
dbname = $dbname
query =
EOF
        # transport_maps.cf
        $self->{'mta'}->buildConfFile( iMSCP::File->new( filename => "$dbDir/virtual_alias_maps.cf" )->set( <<"EOF" ));
user = $sqlUser
password = $sqlUserHost
hosts = $dbHost
dbname = $dbname
query =
EOF
    }

    # Add configuration in the main.cf file
    my $dbType = $self->getDbType();
    $self->{'mta'}->postconf(
        virtual_alias_domains   => { values => [ '' ], empty => TRUE },
        virtual_alias_maps      => { values => [ "proxy:$dbType:$dbDir/virtual_alias_maps.cf" ] },
        virtual_mailbox_domains => { values => [ "proxy:$dbType:$dbDir/virtual_mailbox_domains.cf" ] },
        virtual_mailbox_maps    => { values => [ "proxy:$dbType:$dbDir/virtual_mailbox_maps.cf" ] },
        relay_domains           => { values => [ "proxy:$dbType:$dbDir/relay_domains.cf" ] },
        transport_maps          => { values => [ "proxy:$dbType:$dbDir/transport_maps.cf" ] }
    );
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
