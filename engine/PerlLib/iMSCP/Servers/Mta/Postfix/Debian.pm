=head1 NAME

 iMSCP::Servers::Mta::Postfix::Debian - i-MSCP (Debian) Postfix server implementation

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2018 by Laurent Declercq <l.declercq@nuxwin.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

package iMSCP::Servers::Mta::Postfix::Debian;

use strict;
use warnings;
use Carp qw/ croak /;
use File::Basename;
use iMSCP::Debug qw/ debug error /;
use iMSCP::Execute qw/ execute /;
use iMSCP::File;
use iMSCP::Service;
use version;
use parent 'iMSCP::Servers::Mta::Postfix::Abstract';

=head1 DESCRIPTION

 i-MSCP (Debian) Postfix server implementation.

=head1 PUBLIC METHODS

=over 4

=item install( )

 See iMSCP::Servers::Abstract::install()

=cut

sub install
{
    my ($self) = @_;

    my $rs = $self->SUPER::install();
    $rs ||= $self->_cleanup();
}

=item postinstall( )

 See iMSCP::Servers::Abstract::postinstall()

=cut

sub postinstall
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->enable( 'postfix' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $self->SUPER::postinstall();
}

=item uninstall( )

 See iMSCP::Servers::Abstract::uninstall()

=cut

sub uninstall
{
    my ($self) = @_;

    my $rs = $self->SUPER::uninstall();
    $rs ||= $self->_restoreConffiles();

    unless ( $rs || !iMSCP::Service->getInstance()->hasService( 'postfix' ) ) {
        $self->{'restart'} ||= 1;
    } else {
        @{$self}{qw/ restart reload /} = ( 0, 0 );
    }

    $rs;
}

=item start( )

 See iMSCP::Servers::Abstract::start()

=cut

sub start
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->start( 'postfix' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item stop( )

 See iMSCP::Servers::Abstract::stop()

=cut

sub stop
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->stop( 'postfix' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item restart( )

 See iMSCP::Servers::Abstract::restart()

=cut

sub restart
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->restart( 'postfix' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item reload( )

 See iMSCP::Servers::Abstract::reload()

=cut

sub reload
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->reload( 'postfix' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item shutdown( $priority )

 See iMSCP::Servers::Abstract::shutdown()

=cut

sub shutdown
{
    my ($self, $priority) = @_;

    return unless my $action = $self->{'restart'} ? 'restart' : ( $self->{'reload'} ? 'reload' : undef );

    iMSCP::Service->getInstance()->registerDelayedAction( 'postfix', [ $action, sub { $self->$action(); } ], $priority );
}

=back

=head PRIVATE METHODS

=over 4

=item _cleanup( )

 Process cleanup tasks

 Return int 0 on success, other on failure

=cut

sub _cleanup
{
    my ($self) = @_;

    return 0 unless version->parse( $main::imscpOldConfig{'PluginApi'} ) < version->parse( '1.5.1' ) && -f "$self->{'cfgDir'}/postfix.old.data";

    iMSCP::File->new( filename => "$self->{'cfgDir'}/postfix.old.data" )->delFile();
}

=item _restoreConffiles( )

 Restore configuration files

 Return int 0 on success, other on failure

=cut

sub _restoreConffiles
{
    return 0 unless -d '/etc/postfix';

    for ( '/usr/share/postfix/main.cf.debian', '/usr/share/postfix/master.cf.dist' ) {
        next unless -f;
        my $rs = iMSCP::File->new( filename => $_ )->copyFile( '/etc/postfix/' . basename( $_ ), { preserve => 'no' } );
        return $rs if $rs;
    }

    my $rs = execute( 'newaliases', \ my $stdout, \ my $stderr );
    debug( $stdout ) if $stdout;
    error( $stderr || 'Unknown error' ) if $rs;
    $rs;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
