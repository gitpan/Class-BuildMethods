package Class::BuildMethods;

use warnings;
use strict;

use Scalar::Util qw/refaddr blessed/;
my $VALID_METHOD_NAME = qr/^[_[:alpha:]][[:word:]]*$/;

=head1 NAME

Class::BuildMethods - Lightweight implementation-agnostic generic methods.

=head1 VERSION

Version 0.10

=cut

our $VERSION = '0.11';

=head1 SYNOPSIS

    use Class::BuildMethods 
        'name',
        rank => { default  => 'private' },
        date => { validate => \&valid_date };

=head1 DESCRIPTION

This class allows you to quickly add simple getter/setter methods to your
classes with optional default values and validation.  We assume no
implementation for your class, so you may use a standard blessed hashref,
blessed arrayref, inside-out objects, etc.  This module B<does not> alter
anything about your class aside from installing requested methods and
optionally adding a C<DESTROY> method.  See L<CLEANING UP> for more
information, particularly the C<destroy> method.

=head1 BASIC METHODS

 package Foo;
 use Class::BuildMethods qw/name rank/;
 
 sub new {
   ... whatever implementation you need
 }

 # later

 my $foo = Foo->new;
 $foo->name('bob');
 print $foo->name;   # prints 'bob'

Using a simple list with C<Class::BuildMethods> adds those methods as
getters/setters to your class.

Note that when using a method as a setter, you may only pass in a single
value.  Arrays and hashes should be passed by reference.

=head1 DEFAULT VALUES

 package Foo;
 use Class::BuildMethods
   'name',
   rank => { default => 'private' };

 # later

 my $foo = Foo->new;
 print $foo->rank;   # prints 'private'
 $foo->rank('corporal');
 print $foo->rank;   # prints 'corporal'

After any method name passed to C<Class::BuildMethods>, you may pass it a hash
reference of constraints.  If a key of "default" is found, the value for that
key will be assigned as the default value for the method.

=head1 VALIDATION

 package Drinking::Buddy;
 use Class::BuildMethods;
   'name',
   age => {
     validate => sub {
        my ($self, $age) = @_;
        die "Too young" if $age < 21;
     }
   };

 # later

 my $bubba = Drinking::Buddy->new;
 $bubba->age(18);   # fatal error
 $bubba->age(21);   # Works
 print $bubba->age; # prints '21'

If a key of "validate" is found, a subroutine is expected as the next
argument.  When setting a value, the subroutine will be called with the
invocant as the first argument and the new value as the second argument.  You
may supply any code you wish to enforce validation.

=cut

sub import { goto &build }

##############################################################################

=head1 ADDING METHODS AT RUNTIME

=head2 build

  Class::BuildMethods->build(
    'name',
    rank => { default => 'private' }
  );

This allows you to add the methods at runtime.  Takes the same arguments as
the import list to the class.

=cut

my %value_for;
my %default_for;
my %methods_for;
my %no_destroy_for;

sub build {
    my $class = shift;
    my ($callpack) = caller();
    $methods_for{$callpack} ||= [];
    while (@_) {
        my $method = shift;
        if ( '[NO_DESTROY]' eq $method ) {
            $no_destroy_for{$callpack} = 1;
            next;
        }
        unless ( $method =~ $VALID_METHOD_NAME ) {
            require Carp;
            Carp::croak("'$method' is not a valid method name");
        }
        $method = "${callpack}::$method";
        push @{ $methods_for{$callpack} } => $method;
        my $constraints;
        my $validation_sub;
        if ( 'HASH' eq ref $_[0] ) {
            $constraints = shift;
            if ( exists $constraints->{default} ) {
                $default_for{$method} = delete $constraints->{default};
            }
            if ( exists $constraints->{validate} ) {
                $validation_sub = delete $constraints->{validate};
            }
            if ( my @keys = keys %$constraints ) {
                require Carp;
                Carp::croak("Unknown constraint keys (@keys) for $method");
            }
        }
        no strict 'refs';

        # XXX Note that the code duplication here is very annoying, yet
        # purposeful.  By not trying anything fancy like building the code and
        # eval'ing it or trying to shove too many conditionals into one sub,
        # we keep them fairly lightweight.
        if ($validation_sub) {
            if ( $default_for{$method} ) {
                *$method = sub {
                    my $self     = shift;
                    my $instance = refaddr $self;
                    unless ( exists $value_for{$method}{$instance} ) {
                        $value_for{$method}{$instance}
                          = $default_for{$method};
                    }
                    return $value_for{$method}{$instance} unless @_;
                    my $new_value = shift;
                    $self->$validation_sub($new_value);
                    $value_for{$method}{$instance} = $new_value;
                    return $self;
                };
            }
            else {
                *$method = sub {
                    my $self     = shift;
                    my $instance = refaddr $self;
                    return $value_for{$method}{$instance} unless @_;
                    my $new_value = shift;
                    $self->$validation_sub($new_value);
                    $value_for{$method}{$instance} = $new_value;
                    return $self;
                };
            }
        }
        else {
            if ( $default_for{$method} ) {
                *$method = sub {
                    my $self     = shift;
                    my $instance = refaddr $self;
                    unless ( exists $value_for{$method}{$instance} ) {
                        $value_for{$method}{$instance}
                          = $default_for{$method};
                    }
                    return $value_for{$method}{$instance} unless @_;
                    $value_for{$method}{$instance} = shift;
                    return $self;
                };
            }
            else {
                *$method = sub {
                    my $self     = shift;
                    my $instance = refaddr $self;
                    return $value_for{$method}{$instance} unless @_;
                    $value_for{$method}{$instance} = shift;
                    return $self;
                };
            }
        }
    }
    unless ( $no_destroy_for{$callpack} ) {
        no strict 'refs';
        *{"${callpack}::DESTROY"} = sub {
            my $self = shift;
            __PACKAGE__->destroy($self);
        };
    }
}

##############################################################################

=head1 CLEANING UP

=head2 destroy

  Class::BuildMethods->destroy($instance);

This method destroys instance data for the instance supplied.

Ordinarily you should never have to call this as a C<DESTROY> method is
installed in your namespace which does this for you.  However, if you need a
custom destroy method, provide the special C<[NO_DESTROY]> token to
C<Class::BuildMethods> when you're creating it.

 use Class::BuildMethods qw(
    name
    rank
    serial
    [NO_DESTROY]
 );

 sub DESTROY {
   my $self shift;
   # whatever cleanup code you need
   Class::BuildMethods->destroy($self);
 }

=cut

sub destroy {
    my ( $class, $object ) = @_;
    my @methods  = $class->_find_methods($object);
    my $instance = refaddr $object;

    if (@methods) {
        foreach my $method (@methods) {
            delete $value_for{$method}{$instance};
        }
    }
    return 1;
}

sub _find_methods {
    my ( $class, $object ) = @_;
    my $instance = refaddr $object;
    my $package = ref $object if blessed $object;
    $package ||= '';
    my @methods;
    if ( !exists $methods_for{$package} ) {
        while ( my ( $method, $instance_hash ) = each %value_for ) {
            if ( exists $instance_hash->{$instance} ) {
                push @methods => $method;
            }
        }
    }
    else {
        @methods = @{ $methods_for{$package} };
    }
    return @methods;
}

# this is a testing hook to ensure that destroyed data is really gone
# do not rely on this method
sub _peek {
    my ( $class, $package, $method, $refaddr ) = @_;
    my $fq_method = "${package}::$method";
    return unless exists $value_for{$fq_method}{$refaddr};
    return $value_for{$fq_method}{$refaddr};
}

=head2 reset

  Class::BuildMethods->reset;   # assumes current package
  Class::BuildMethods->reset($package);

This methods deletes all of the values for the methods added by
C<Class::BuildMethods>.  Any methods with default values will now have their
default values restored.  It does not remove the methods.  Returns the number
of methods reset.

=cut

sub reset {
    my ( $class, $package ) = @_;
    unless ( defined $package ) {
        ($package) = caller();
    }
    return unless $methods_for{$package};
    my @methods = @{ $methods_for{$package} };
    delete @value_for{@methods};
    return scalar @methods;
}

##############################################################################

=head2 reclaim

  Class::BuildMethods->reclaim;   # assumes current package
  Class::BuildMethods->reclaim($package);
 
Like C<reset> but more final.  Removes any values set for methods, any default
values and pretty much any trace of a given module from this package.  It
B<does not> remove the methods.  Any attempt to use the the autogenerated
methods after this method is called is not guaranteed.

=cut

sub reclaim {
    my ( $class, $package ) = @_;
    unless ( defined $package ) {
        ($package) = caller();
    }
    return unless $methods_for{$package};
    my @methods = @{ $methods_for{$package} };
    delete $methods_for{$package};
    delete $no_destroy_for{$package};
    delete @default_for{@methods};
    delete @value_for{@methods};
    return scalar @methods;
}

##############################################################################

=head2 packages

  my @packages = Class::BuildMethods->packages;

Returns a sorted list of packages for which methods have been built.  If
C<reclaim> has been called for a package, this method will not return that
package.  This is generally useful if you need to do a global code cleanup
from a remote package:

 foreach my $package (Class::BuildMethods->packages) {
    Class::BuildMethods->reclaim($package);
 }
 # then whatever teardown you need

In reality, you probably will never need this method.

=cut

sub packages {
    return sort keys %methods_for;
}

##############################################################################

=head1 DEBUGGING

=head2 dump

  my $hash_ref = Class::BuildMethods->dump($object);

The C<dump()> method returns a hashref.  The keys are the method names and the
values are whatever they are currently set to.  This method is provided to
ease debugging as merely dumping an inside-out object generally does not
return its structure.

=cut

sub dump {
    my ( $class, $object ) = @_;
    my @methods  = $class->_find_methods($object);
    my $instance = refaddr $object;

    my %dump_for;
    if (@methods) {
        foreach my $method (@methods) {
            my ($attribute) = $method =~ /^.*::([^:]+)$/;
            $dump_for{$attribute} = $value_for{$method}{$instance};
        }
    }
    return \%dump_for;
}

=head1 CAVEATS

Some people will not be happy that if they need to store an array or a hash
they must pass them by reference as each generated method expects a single
value to be passed in when used as a "setter".  This is because this module is
designd to be I<simple>.  It's very lightweight and very fast.

=head1 AUTHOR

Curtis "Ovid" Poe, C<< <ovid@cpan.org> >>

=head1 ACKNOWLEDGEMENTS

Thanks to Kineticode, Inc. for supporting development of this package.

=head1 BUGS

Please report any bugs or feature requests to
C<bug-class-buildmethods@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Class-BuildMethods>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2005 Curtis "Ovid" Poe, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;    # End of Class::BuildMethods
## Please see file perltidy.ERR
