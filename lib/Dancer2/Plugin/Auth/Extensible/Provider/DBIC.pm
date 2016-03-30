package Dancer2::Plugin::Auth::Extensible::Provider::DBIC;

use Carp;
use Dancer2::Core::Types qw/Int Str/;
use DateTime;
use DBIx::Class::ResultClass::HashRefInflator;
use String::CamelCase qw(camelize);

use Moo;
with "Dancer2::Plugin::Auth::Extensible::Role::Provider";
use namespace::clean;

our $VERSION = '0.502';

=head1 NAME 

Dancer2::Plugin::Auth::Extensible::Provider::DBIC - authenticate via the
L<Dancer2::Plugin::DBIC> plugin


=head1 DESCRIPTION

This class is an authentication provider designed to authenticate users against
a database, using L<Dancer2::Plugin::DBIC> to access a database.

See L<Dancer2::Plugin::DBIC> for how to configure a database connection
appropriately; see the L</CONFIGURATION> section below for how to configure this
authentication provider with database details.

See L<Dancer2::Plugin::Auth::Extensible> for details on how to use the
authentication framework.


=head1 CONFIGURATION

This provider tries to use sensible defaults, in the same manner as
L<Dancer2::Plugin::Auth::Extensible::Provider::Database>, so you may not need
to provide much configuration if your database tables look similar to those.

The most basic configuration, assuming defaults for all options, and defining a
single authentication realm named 'users':

    plugins:
        Auth::Extensible:
            realms:
                users:
                    provider: 'DBIC'

You would still need to have provided suitable database connection details to
L<Dancer2::Plugin::DBIC>, of course;  see the docs for that plugin for full
details, but it could be as simple as, e.g.:

    plugins:
        Auth::Extensible:
            realms:
                users:
                    provider: 'DBIC'
        DBIC:
            default:
                dsn: dbi:mysql:database=mydb;host=localhost
                schema_class: MyApp::Schema
                user: user
                pass: secret

A full example showing all options:

    plugins:
        Auth::Extensible:
            realms:
                users:
                    provider: 'DBIC'

                    # Optionally specify the sources of the data if not the
                    # defaults (as shown).  See notes below for how these
                    # generate the resultset names.  If you use standard DBIC
                    # resultset names, then these and the column names are the
                    # only settings you might need.  The relationships between
                    # these resultsets is automatically introspected by
                    # inspection of the schema.
                    users_source: 'user'
                    roles_source: 'role'
                    user_roles_source: 'user_role'

                    # optionally set the column names
                    users_username_column: username
                    users_password_column: password
                    roles_role_column: role

                    # This plugin supports the DPAE record_lastlogin functionality.
                    # Optionally set the column name:
                    users_lastlogin_column: lastlogin

                    # Optionally set columns for user_password functionality in
                    # Dancer2::Plugin::Auth::Extensible
                    users_pwresetcode_column: pw_reset_code
                    users_pwchanged_column:   # Time of reset column. No default.

                    # Days after which passwords expire. See logged_in_user_password_expired
                    # functionality in Dancer2::Plugin::Auth::Extensible
                    password_expiry_days:       # No default

                    # Optionally set the name of the DBIC schema
                    schema_name: myschema

                    # Optionally set additional conditions when searching for the
                    # user in the database. These are the same format as required
                    # by DBIC, and are passed directly to the DBIC resultset search
                    user_valid_conditions:
                        deleted: 0
                        account_request:
                            "<": 1

                    # Optionally specify a key for the user's roles to be returned in.
                    # Roles will be returned as role_name => 1 hashref pairs
                    roles_key: roles

                    # Optionally specify the algorithm when encrypting new passwords
                    encryption_algorithm: SHA-512

                    # If you don't use standard DBIC resultset names, you might
                    # need to configure these instead:
                    users_resultset: User
                    roles_resultset: Role
                    user_roles_resultset: UserRole

                    # Deprecated settings. The following settings were renamed for clarity
                    # to the *_source settings
                    users_table:
                    roles_table:
                    user_roles_table:


=over

=cut

sub deprecated_setting {
    my ( $setting, $replacement ) = @_;
    carp __PACKAGE__, " config setting \"$setting\" is deprecated.",
      " Use \"$replacement\" instead.";
}

sub BUILDARGS {
    my $class = shift;
    my %args = ref( $_[0] ) eq 'HASH' ? %{ $_[0] } : @_;

    my $app = $args{plugin}->app;

    # backwards compat

    if ( $args{users_table} ) {
        deprecated_setting( 'users_table', 'users_source' );
        $args{users_source} = delete $args{users_table}
          if !$args{users_source};
    }

    if ( $args{roles_table} ) {
        deprecated_setting( 'roles_table', 'roles_source' );
        $args{roles_source} = delete $args{roles_table}
          if !$args{roles_source};
    }

    if ( $args{user_roles_table} ) {
        deprecated_setting( 'user_roles_table', 'user_roles_source' );
        $args{user_roles_source} = delete $args{user_roles_table}
          if !$args{user_roles_source};
    }

    return \%args;
}

=item user_source

Specifies the source name that contains the users. This will be camelized to generate
the resultset name. The relationship to user_roles_source will be introspected from
the schema.

=item role_source

Specifies the source name that contains the roles. This will be camelized to generate
the resultset name. The relationship to user_roles_source will be introspected from
the schema.

=item user_roles_source

Specifies the source name that contains the user_roles joining table. This will be
camelized to generate the resultset name. The relationship to the user and role
source will be introspected from the schema.

=item users_username_column

Specifies the column name of the username column in the users table

=item users_password_column

Specifies the column name of the password column in the users table

=item roles_role_column

Specifies the column name of the role name column in the roles table

=item schema_name

Specfies the name of the L<Dancer2::Plugin::DBIC> schema to use. If not
specified, will default in the same manner as the DBIC plugin.

=item user_valid_conditions

Specifies additional search parameters when looking up a user in the users table.
For example, you might want to exclude any account this is flagged as deleted
or disabled.

The value of this parameter will be passed directly to DBIC as a search condition.
It is therefore possible to nest parameters and use different operators for the
condition. See the example config above for an example.

=item roles_key

Specifies a key for the returned user hash to also return the user's roles in.
The value of this key will contain a hash ref, which will contain each
permission with a value of 1. In your code you might then have:

    my $user = logged_in_user;
    return foo_bar($user);

    sub foo_bar
    {   my $user = shift;
        if ($user->{roles}->{beer_drinker}) {
           ...
        }
    }

This isn't intended to replace the L<Dancer2::Plugin::Auth::Extensible/user_has_role>
keyword. Instead it is intended to make it easier to access a user's roles if the
user hash is being passed around (without requiring access to the user_has_role
keyword in other modules).

=item users_resultset

=item roles_resultset

=item user_roles_resultset

These configuration values are provided for fine-grain tuning of your DBIC
resultset names. If you use standard DBIC naming practices, you will not need
to configure these, and they will be generated internally automatically.

=back

=head1 SUGGESTED SCHEMA

Please see Schema1 in the tests directory for a suggested schema.

If producing a schema from scratch, it is recommended that the default
resultset and column names are used, as per the default configuration.

=cut

has dancer2_plugin_dbic => (
    is      => 'ro',
    lazy    => 1,
    default => sub { $_[0]->plugin->app->with_plugin('Dancer2::Plugin::DBIC') },
    handles => { dbic_schema => 'schema' },
    init_arg => undef,
);

has schema_name => ( is => 'ro', );

has schema => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        $self->schema_name
          ? $self->dbic_schema( $self->schema_name )
          : $self->dbic_schema;
    },
);

has password_expiry_days => (
    is => 'ro',
    isa => Int,
);

has roles_key => (
    is => 'ro',
);

has roles_resultset => (
    is      => 'ro',
    lazy    => 1,
    default => sub { camelize( $_[0]->roles_source ) },
);

has roles_role_column => (
    is      => 'ro',
    default => 'role',
);

has roles_source => (
    is      => 'ro',
    default => 'role',
);

has users_resultset => (
    is      => 'ro',
    lazy    => 1,
    default => sub { camelize( $_[0]->users_source ) },
);

has users_source => (
    is      => 'ro',
    default => 'user',
);

has users_lastlogin_column => (
    is      => 'ro',
    default => 'lastlogin',
);

has users_password_column => (
    is      => 'ro',
    default => 'password',
);

has users_pwchanged_column => (
    is => 'ro',
);

has users_pwresetcode_column => (
    is      => 'ro',
    default => 'pw_reset_code',
);

has users_username_column => (
    is      => 'ro',
    default => 'username',
);

has user_user_roles_relationship => (
    is      => 'ro',
    lazy    => 1,
    default => sub { $_[0]->_build_user_roles_relationship('user') },
);

has user_roles_resultset => (
    is      => 'ro',
    lazy    => 1,
    default => sub { camelize( $_[0]->user_roles_source ) },
);

has user_roles_source => (
    is      => 'ro',
    default => 'user_roles',
);

has user_valid_conditions => (
    is      => 'ro',
    default => sub { {} },
);

has role_user_roles_relationship => (
    is      => 'ro',
    lazy    => 1,
    default => sub { $_[0]->_build_user_roles_relationship('role') },
);

has user_roles_result_class => (
    is      => 'ro',
    lazy    => 1,
    default => sub {
        my $self = shift;
        # undef if roles are disabled
        return undef if $self->plugin->disable_roles;
        return $self->schema->resultset( $self->user_roles_resultset )
          ->result_source->result_class;
    },
);

sub _build_user_roles_relationship {
    my ( $self, $name ) = @_;

    return undef if $self->plugin->disable_roles;

    # Introspect result sources to find relationships

    my $user_roles_class =
      $self->schema->resultset( $self->user_roles_resultset )
      ->result_source->result_class;

    my $resultset_name = "${name}s_resultset";

    my $result_source =
      $self->schema->resultset( $self->$resultset_name )->result_source;

    foreach my $relname ( $result_source->relationships ) {
        my $info = $result_source->relationship_info($relname);
        my %cond = %{ $info->{cond} };
        if (   $info->{class} eq $user_roles_class
            && $info->{attrs}->{accessor} eq 'multi'
            && $info->{attrs}->{join_type} eq 'LEFT'
            && scalar keys %cond == 1 )
        {
            return $relname;
        }
    }
}

has role_relationship => (
    is      => 'ro',
    lazy    => 1,
    default => sub { $_[0]->_build_relationship('role') },
);

has user_relationship => (
    is      => 'ro',
    lazy    => 1,
    default => sub { $_[0]->_build_relationship('user') },
);

sub _build_relationship {
    my ( $self, $name ) = @_;

    return undef if $self->plugin->disable_roles;

    # Introspect result sources to find relationships

    my $user_roles_class =
      $self->schema->resultset( $self->user_roles_resultset )
      ->result_source->result_class;

    my $resultset_name = "${name}s_resultset";

    my $result_source =
      $self->schema->resultset( $self->$resultset_name )->result_source;

    my $user_roles_relationship = "${name}_user_roles_relationship";

    my ($relationship) = keys %{
        $result_source->reverse_relationship_info(
            $self->$user_roles_relationship
        )
    };

    return $relationship;
}

# Returns a DBIC rset for the user
sub _user_rset {
    my ($self, $column, $value, $options) = @_;
    my $username_column       = $self->users_username_column;
    my $user_valid_conditions = $self->user_valid_conditions;

    my $search_column = $column eq 'username'
                      ? $username_column
                      : $column eq 'pw_reset_code'
                      ? $self->users_pwresetcode_column
                      : $column;

    # Search based on standard username search, plus any additional
    # conditions in ignore_user
    my $search = { %$user_valid_conditions, $search_column => $value };

    # Look up the user
    $self->schema->resultset($self->users_resultset)->search($search, $options);
}

sub authenticate_user {
    my ($self, $username, $password, %options) = @_;

    # Look up the user:
    my $user = $self->get_user_details($username);
    return unless $user;

    # OK, we found a user, let match_password (from our base class) take care of
    # working out if the password is correct
    my $password_column = $self->users_password_column;
    if ( my $match =
        $self->match_password( $password, $user->{$password_column} ) )
    {
        if ( $options{lastlogin} ) {
            if ( my $lastlogin = $user->{lastlogin} ) {
                my $db_parser = $self->schema->storage->datetime_parser;
                $lastlogin = $db_parser->parse_datetime($lastlogin);

                # SysPete: comment out next line since this is not used
                # anywhere and is undocumented
                #$self->plugin->app->session->write($options{lastlogin} => $lastlogin);
            }
            $self->set_user_details( $username,
                $self->users_lastlogin_column => DateTime->now, );
        }
        return $match;
    }
    return;    # Make sure we return nothing
}

sub set_user_password {
    my ( $self, $username, $password ) = @_;
    my $encrypted       = $self->encrypt_password($password);
    my $password_column = $self->users_password_column;
    my %update          = ( $password_column => $encrypted );
    if ( my $pwchanged = $self->users_pwchanged_column ) {
        $update{$pwchanged} = DateTime->now;
    }
    $self->set_user_details( $username, %update );
}

# Return details about the user.  The user's row in the users table will be
# fetched and all columns returned as a hashref.
sub get_user_details {
    my ($self, $username) = @_;
    return unless defined $username;

    # Look up the user
    my $users_rs = $self->_user_rset(username => $username);

    # Inflate to a hashref, otherwise it's returned as a DBIC rset
    $users_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    my ($user) = $users_rs->all;
    
    if (!$user) {
        $self->plugin->app->log( 'debug', "No such user $username" );
        return;
    } else {
        if (my $pwchanged = $self->users_pwchanged_column) {
            # Convert to DateTime object
            my $db_parser = $self->schema->storage->datetime_parser;
            $user->{$pwchanged} = $db_parser->parse_datetime($user->{$pwchanged})
                if $user->{$pwchanged};
        }
        if (my $roles_key = $self->roles_key) {
            my @roles = @{$self->get_user_roles($username)};
            my %roles = map { $_ => 1 } @roles;
            $user->{$roles_key} = \%roles;
        }
        return $user;
    }
}

# Find a user based on a password reset code
sub get_user_by_code {
    my ($self, $code) = @_;

    my $username_column = $self->users_username_column;
    my $users_rs        = $self->_user_rset(pw_reset_code => $code);
    my ($user)          = $users_rs->all;
    return unless $user;
    $user->$username_column;
}

sub create_user {
    my ($self, %user) = @_;
    my $username_column = $self->users_username_column;
    my $username        = delete $user{username} # Prevent attempt to update wrong key
        or die "Username needs to be specified for create_user";
    $self->schema->resultset($self->users_resultset)->create({
        $username_column => $username
    });
    $self->set_user_details($username, %user);
}

# Update a user. Username is provided in the update details
sub set_user_details {
    my ($self, $username, %update) = @_;

    die "Username to update needs to be specified"
        unless $username;

    # Look up the user
    my ($user) = $self->_user_rset(username => $username)->all;
    $user or return;

    # Are we expecting a user_roles key?
    if (my $roles_key = $self->roles_key) {
        if (my $new_roles = delete $update{$roles_key}) {

            my $roles_role_column     = $self->roles_role_column;
            my $users_username_column = $self->users_username_column;

            my @all_roles      = $self->schema->resultset($self->roles_resultset)->all;
            my %existing_roles = map { $_ => 1 } @{$self->get_user_roles($username)};

            foreach my $role (@all_roles) {
                my $role_name = $role->$roles_role_column;

                if ( $new_roles->{$role_name} && !$existing_roles{$role_name} )
                {
                    # Needs to be added
                    $self->schema->resultset( $self->user_roles_resultset )
                      ->create(
                        {
                            $self->user_relationship => {
                                $users_username_column => $username,
                                %{ $self->user_valid_conditions }
                            },
                            $self->role_relationship => {
                                $roles_role_column => $role_name
                            },
                        }
                      );
                }
                elsif ( !$new_roles->{$role_name}
                    && $existing_roles{$role_name} )
                {
                    # Needs to be removed
                    $self->schema->resultset( $self->user_roles_resultset )
                      ->search(
                        {
                            $self->user_relationship
                              . ".$users_username_column" => $username,
                            $self->role_relationship
                              . ".$roles_role_column" => $role_name,
                        },
                        {
                            join => [
                                $self->user_relationship,
                                $self->role_relationship
                            ],
                        }
                      )->delete;
                }
            }
        }
    }

    # Move password reset code between keys if required
    if (my $users_pwresetcode_column = $self->users_pwresetcode_column) {
        if (exists $update{pw_reset_code}) {
            my $pw_reset_code = delete $update{pw_reset_code};
            $update{$users_pwresetcode_column} = $pw_reset_code;
        }
    }
    $user->update({%update});
    # Update $username if it was submitted in update
    $username = $update{username} if $update{username};
    return $self->get_user_details($username);
}

sub get_user_roles {
    my ($self, $username) = @_;

    my $role_relationship            = $self->role_relationship;
    my $user_user_roles_relationship = $self->user_user_roles_relationship;
    my $roles_role_column            = $self->roles_role_column;

    my $options =
      { prefetch => { $user_user_roles_relationship => $role_relationship } };

    my ($user) = $self->_user_rset(username => $username, $options)->all;

    if (!$user) {
        $self->plugin->app->log( 'debug',
            "No such user $username when looking for roles" );
        return;
    }

    my @roles;
    foreach my $ur ($user->$user_user_roles_relationship)
    {
        my $role = $ur->$role_relationship->$roles_role_column;
        push @roles, $role;
    }

    \@roles;
}

sub password_expired {
    my ($self, $user) = @_;
    my $expiry   = $self->password_expiry_days or return 0; # No expiry set

    if (my $pwchanged = $self->users_pwchanged_column) {
        my $last_changed = $user->{$pwchanged}
            or return 1; # If not changed then report expired
        my $duration     = $last_changed->delta_days(DateTime->now);
        $duration->in_units('days') > $expiry ? 1 : 0;
    } else {
        die "users_pwchanged_column not configured";
    }
}

1;
