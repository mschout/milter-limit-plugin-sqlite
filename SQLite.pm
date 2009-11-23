=head1 NAME

Milter::Limit::Plugin::SQLite - SQLite backend for Milter::Limit

=head1 SYNOPSIS

 my $milter = Milter::Limit->instance('SQLite');

=head1 DESCRIPTION

This module implements the C<Milter::Limit> backend using a SQLite data
store.

=head1 CONFIGURATION

The C<[driver]> section of the configuration file must specify the following items:

=over 4

=item home [optional]

The directory where the database files should be stored.

default: C<state_dir>

=item file [optional]

The database filename.

default: C<stats.db>

=item table [optional]

Table name that will store the statistics.

default: C<milter>

=back

=cut

package Milter::Limit::Plugin::SQLite;

use strict;
use base qw(Milter::Limit::Plugin Class::Accessor);
use DBI;
use DBIx::Connector;
use File::Spec;
use Milter::Limit::Util;

__PACKAGE__->mk_accessors(qw(_conn table));

sub init {
    my $self = shift;

    $self->init_defaults;

    Milter::Limit::Util::make_path($self->config_get('driver', 'home'));

    $self->table( $self->config_get('driver', 'table') );

    # setup the database
    $self->init_database;
}

sub init_defaults {
    my $self = shift;

    $self->config_defaults('driver',
        home  => $self->config_get('global', 'state_dir'),
        file  => 'stats.db',
        table => 'milter');
}

sub db_file {
    my $self = shift;

    my $home = $self->config_get('driver', 'home');
    my $file = $self->config_get('driver', 'file');

    return File::Spec->catfile($home, $file);
}

sub _dbh {
    my $self = shift;

    return $self->_conn->dbh;
}

sub init_database {
    my $self = shift;

    # setup connection to the database.
    my $db_file = $self->db_file;

    my $conn = DBIx::Connector->new("dbi:SQLite:dbname=$db_file", '', '', {
        PrintError => 0,
        AutoCommit => 1 })
        or die "failed to initialize SQLite: $!";

    $self->_conn($conn);

    unless ($self->table_exists($self->table)) {
        $self->create_table($self->table);
    }

    # make sure the db file has the right owner.
    my $uid = $self->config_get('global', 'user');
    my $gid = $self->config_get('global', 'group');

    chown $uid, $gid, $db_file or die "chown($db_file): $!";
}

sub query {
    my ($self, $from) = @_;

    $from = lc $from;

    my $rec = $self->_retrieve($from);

    unless (defined $rec) {
        # initialize new record for sender
        $rec = $self->_create($from)
            or return 0;    # I give up
    }

    my $start  = $$rec{first_seen} || time;
    my $count  = $$rec{messages} || 0;
    my $expire = $self->config_get('global', 'expire');

    # reset counter if it is expired
    if ($start < time - $expire) {
        $self->_reset($from);
        return 1;
    }

    # update database for this sender.
    $self->_update($from);

    return $count + 1;
}

# return true if the given db table exists.
sub table_exists {
    my ($self, $table) = @_;

    $self->_dbh->do("select 1 from $table limit 0")
        or return 0;

    return 1;
}

# create the given table as the stats table.
sub create_table {
    my ($self, $table) = @_;

    my $dbh = $self->_dbh;

    $dbh->do(qq{
        create table $table (
            sender varchar (255),
            first_seen timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            messages integer NOT NULL DEFAULT 0,
            PRIMARY KEY (sender)
        )
    }) or die "failed to create table $table: $DBI::errstr";

    $dbh->do(qq{
        create index ${table}_first_seen_key on $table (first_seen)
    }) or die "failed to create first_seen index: $DBI::errstr";
}

## CRUD methods
sub _create {
    my ($self, $sender) = @_;

    my $table = $self->table;

    $self->_dbh->do(qq{insert or replace into $table (sender) values (?)},
        undef, $sender)
        or warn "failed to create sender record: $DBI::errstr";

    return $self->_retrieve($sender);
}

sub _retrieve {
    my ($self, $sender) = @_;

    my $table = $self->table;

    my $query = qq{
        select
            sender,
            messages,
            strftime('%s',first_seen) as first_seen
        from
            $table
        where
            sender = ?
    };

    return $self->_dbh->selectrow_hashref($query, undef, $sender);
}

sub _update {
    my ($self, $sender) = @_;

    my $table = $self->table;

    my $query = qq{update $table set messages = messages + 1 where sender = ?};

    return $self->_dbh->do($query, undef, $sender);
}

sub _reset {
    my ($self, $sender) = @_;

    my $table = $self->table;

    $self->_dbh->do(qq{
        update
            $table
        set
            messages   = 1,
            first_seen = CURRENT_TIMESTAMP
        where
            sender = ?
    }, undef, $sender)
        or warn "failed to reset $sender: $DBI::errstr";
}

=head1 SOURCE

You can contribute or fork this project via github:

http://github.com/mschout/milter-limit

 git clone git://github.com/mschout/milter-limit.git

=head1 AUTHOR

Michael Schout E<lt>mschout@cpan.orgE<gt>

=head1 COPYRIGHT & LICENSE

Copyright 2009 Michael Schout.

This program is free software; you can redistribute it and/or modify it under
the terms of either:

=over 4

=item *

the GNU General Public License as published by the Free Software Foundation;
either version 1, or (at your option) any later version, or

=item *

the Artistic License version 2.0.

=back

=head1 SEE ALSO

L<Milter::Limit::Plugin>,
L<Milter::Limit>

=cut

1;
