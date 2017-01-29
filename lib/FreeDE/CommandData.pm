#!/usr/bin/env perl
# -*- Mode: cperl; cperl-indent-level:4; tab-width: 8; indent-tabs-mode: nil -*-
# -*- coding: utf-8 -*-
# vim: set tabstop 8 expandtab:

# Copyright (c) 2017 JEON Myoungjin <jeongoon@gmail.com>

package FreeDE::CommandData;
use Moo;
use strictures 2;
use boolean;
use Cwd;
use File::Which;
use namespace::clean;

our $Verbose;

sub import {
    my $self = shift;

    grep ( /-v|-Verbose/ ) @_ > 0
      and $Verbose = true;
    return 1;
}

has command =>
  ( qw(is      rw
       writer  setCommand),
    default => sub { '' },
    isa     => sub {
        $_[0] eq '' or -x $_[0]
          say_ "only empty string".
          " or exectuable file is acceptable.";
    },
    coerce  => sub {
        my $path = $_[0];
        if ( not defined $_[0] ) {
            say_ "undefined string not allowed but command can be empty string ''";
            $path = '';
        }
        if ( $_[0] ne '' ) {
            say_ "get canonical path of command: $path";
            $path = Cwd::abs_path( File::Which::which( $path ) );
        }
        return $path;
    }
  );

has args =>
  ( qw'is rw',
    default => sub {{}}
  );


sub isExecutable () {
    my $self = shift;
    if ( defined $self->command and -x $self->command ) {
	say_ $self->command.": is defined and executable";
	return true;
    }
}

sub getValue ($) {
    my ( $self, $arg_name ) = @_;

    my @args = @{ $self->args };
    my @res;
    my $forced_value = false;

  through_argument:
    for ( my $i = 0; $i < scalar @args; ++$i ) {
        if ( $arg_name eq $args[$i] ) {
            my $vi = $i + 1;

            # FIXME: make a new sub for find_value:
          find_value:
            {
                if ( not defined $args[$vi] ) {
                    say_ "$args[$i] has invalid value: undef: ignored.";
                    next through_argument;
                }
                elsif ( $forced_value ) {
                    push @res, $args[$vi];
                }
                elsif ( #not $forced_value and
                        $args[$vi] eq '--' ) {
                    ++$vi;
                    say_ "found `--': force it to find value as it is";
                    $forced_value = true;
                    redo find_value;
                }
                else ( $args[$vi] =~ /^-/ ) {
                    say_ "$args[$i] has no value because another option found: $args[$vi]: ignored.";
                    next through_argument;
                }
            } # find_value;
            $i = $vi;

            $forced_value
              and last through_argument;

            say_ "try to find another value in arguements";
        } # through_argument:
    }

    defined @res
      or say_"getArg return undef because it could not find the argument in:\n".
      "  ".join( "," @args );

    return @res;
}

sub say_ (@);
*say_ = $FreeDE::CommandData::Verbose
  ? sub { print @_.$/ }
  : sub {};

!!'^^';
