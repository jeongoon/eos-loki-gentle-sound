# -*- Mode: cperl; cperl-indent-level:4; tab-width: 8; indent-tabs-mode: nil -*-
# -*- coding: utf-8 -*-
# vim: set tabstop 8 expandtab:

# Copyright (c) 2016,2017 JEON Myoungjin <jeongoon@gmail.com>

package FreeDE::App;

use strict; use warnings;
use boolean;
use File::Spec;
use File::HomeDir;
use Time::HiRes   qw(CLOCK_REALTIME);
use Path::Tiny;
use Safe::Isa;

use parent 'Exporter';
use version 0.77; our $VERSION = version->declare( 'v0.1' );

our @EXPORT_OK = qw(getAppName          isDebugging     isVerbose
                    dmsg        leave   info
                    app         fs
                    myHomeDir   myHome  myDataDir
                    loadConfig
                    getClockNow
                    slurpFile
                    getConfigPath       prepareConfigPath
                    getCachePath        prepareCachePath
                    getDataPath         prepareDataPath
                  );

our %EXPORT_TAGS = ( 'auto' => [ qw(getAppName isDebugging isVerbose) ],
                     'msg'  => [ qw(dmsg leave info) ],
                     'xdg'  => [ qw(getConfigPath       prepareConfigPath
                                    getCachePath        prepareCachePath
                                    getDataPath         prepareDataPath) ],
                   );

sub app () { __PACKAGE__  }
sub fs  () { 'File::Spec' }
sub myHomeDir () { File::HomeDir->my_home }
sub myDataDir () { File::HomeDir->my_data }
# aliases
sub myHome    (); *myHome = \&myHomeDir;

sub msg_fmt_ ($$$) {
    my ( $label, $file, $line ) = @_[ $#_-2 .. $#_ ];

    defined $label and $label .= " ";
    defined $file  or  $file   = "";
    defined $line  and $line   = ":$line";

    "[${label}$::AppName:$$] $file$line: "
}

# simple log methods
sub info  (@); # like warn
sub leave (@); # like die but say on STDOUT
sub dmsg  (@); # like say STDERR, something

sub dbg_say (@) {
    my $fh    = shift;
    my $label = shift;
    my ( undef, $file, $line ) =  caller(1);
    ( undef, undef, $file ) = fs->splitpath( $file );
    print $fh msg_fmt_( $label, $file, $line ), @_, $/;
}

my $die_sub  = sub (@) { dbg_say( *STDOUT, 'FATAL', @_ );
                         exit (defined $!) ? $! : 9 }; # 9: same as die()
my $dmsg_sub = sub (@) { dbg_say( *STDERR, 'DEBUG', @_ ); };
my $info_sub = sub (@) { dbg_say( *STDOUT, 'INFRM', @_ ); };

#$Exporter::Verbose = 1;

sub import {
    my $self = shift;

    # I made subroutine for easy to derive import subroutine.
    my @exporter_args;
    @exporter_args = $self->checkAppArgs_( \@_ );

    # make Exporter::export_to_level can handle default tags ...
    # XXX something wrong with export_to_level(), so I need to put twice.
    unshift @exporter_args, ( ':auto' ) x 2;
    $self->Exporter::export_to_level( 1, @exporter_args );
}

sub checkAppArgs_ ($) {
    my @a = @{ pop@_ };
    my @left;
    my $is_app_toplevel = true;

    while ( scalar @a ) {
        my $opt = shift @a;
        if    ( $opt eq '-subLibary' ) { $is_app_toplevel = false  }
        elsif ( $opt eq '-AppName'   ) { $::AppName = shift @a; }
        elsif ( $opt eq '-Debug'     ) { $::Debug   = getBoolean( shift @a ); }
        elsif ( $opt eq '-Verbose'   ) { $::Verbose = getBoolean( shift @a ); }
        elsif ( $opt =~ /^-/         ) { die_sub->( "unknown option: $opt" );  }
        else                           { push @left, $opt;  }
    }

    $is_app_toplevel or return @left;

    $::AppName ||= 'myApp';
    $::Debug   ||= false;
    $::Verbose ||= false;

    if ( $::Debug->isTrue ) {
        *dmsg = $dmsg_sub;      *leave = $die_sub;
    }
    else { # simpler message
        *dmsg = sub (@) {};     *leave = \&CORE::die;
    }

    if ( $::Verbose->isTrue ) {
        *info = $::Debug
          ? $info_sub
          : sub (@) { say STDERR @_  };   }
    else            { *info = sub (@) {}; }

    return @left;
}

sub getAppName  () { "$::AppName" }
sub isVerbose   () { boolean( $::Verbose ) } # copy
sub isDebugging () { boolean( $::Debug   ) } # copy

sub getBoolean  ($) {
    my $var = pop;
    defined $var or return false;

    # note: "$var" -> ensure the value for boolean object :-(
    if    ( "$var" =~ /^(1|y|yes|t|true)$/i )    { return true;  }
    elsif ( "$var" =~ /^(0|n|no|nil|false)$|/i ) { return false; }
    else {
        $info_sub->( "unknown boolean string: ".
                     "$var: assume that it ha sa false value" );
        return false;
    }

    $die_sub->( 'getBoolean(): FIXME: an unexpected bug' );
}

sub getClockNow () {
    Time::HiRes::clock_gettime( CLOCK_REALTIME );
}

sub getConfigPath () { fs->catfile( myHome, '.config', getAppName ) }
sub getCachePath  () { fs->catfile( myHome, '.cache',  getAppName ) }
# aliases
sub getDataPath   (); *getDataPath = myDataDir;

sub prepareConfigPath { make_xdg_dir_( [ '.config' ], @_ ) }
sub prepareCachePath  { make_xdg_dir_( [ '.cache'  ], @_ ) }
sub prepareDataPath   { make_xdg_dir_( [ qw/.local share/ ], @_ ) }

sub make_xdg_dir_( $$;$$$ ) {
    my ( $app_name, @base_dirs, $mask, %opt );

    # ignore class or instancea
    $_[0] eq app or $_[0]->$_isa(app) and shift;
    # XXX: App name
    $app_name = getAppName;

    # check option ( only mask for now)
    %opt = ( defined $_[-1] and ref( $_[-1] ) eq 'HASH' )
      ? %{ &pop } : @_;

    # xdg base directory array;
    @base_dirs = @{ &pop };
    exists $opt{'mask'} and $mask = $opt{'mask'};

    my ( $volume, $dirs_, undef )
      = fs->splitpath( myHome, !! 'last one is not a file.' );
    my @dirs = fs->splitdir( $dirs_ );

    my $xdg_dir = fs->catdir( $volume, @dirs, @base_dirs, $app_name );
    dmsg "xdg dir: $xdg_dir";

    if ( ! -d $xdg_dir ) {
        info "$xdg_dir does not exists: making one";
        mkdir $xdg_dir or mkdir_recursively_( $volume, \@dirs, $mask );
    }

    -d $xdg_dir ? $xdg_dir : undef;
}

sub loadConfig ($) {
    # XXX: use Sereal;
}

sub mkdir_recursively_ ($$;$$$) {
    my ( $volume, $dirs, $mask ) = @_;
    $mask ||= 0777;

    my $parent_path = fs->catdir( $volume, undef );
    my $path;
    for my $i ( 0 .. $#{$dirs} ) {
        $path = fs->catdir( $volume, @{$dirs}[ 0..$i ] );
        -d $path or mkdir( $path, $mask ) or
          -d $path or return ( false, $parent_path );
        $parent_path = $path;
    }

    true;
}

sub get_path_object_ ($) {
    my $path = "$_[-1]";
    -e $path or return path( fs->devnull );

    require Safe::Isa;
    Safe::Isa->import();
    our $_isa; # need to declare.

    $path = path( $path) if not $path->$_isa( 'Path::Tiny' );

    $path;
}

sub slurpFile ($;$$) {
    # Path::Tiny::slurp() is great to use
    # but I prefer not to die when failed to locate file

    my $encoding_utf8 = false;
    my $last_arg = pop;
    if ( defined $last_arg and ref $last_arg eq 'HASH' ) {
        exists $last_arg->{'encoding'}
          and  $last_arg->{'encoding'} =~ m/utf-*8/i
          and $encoding_utf8 = true;

        $last_arg = pop;
    }
    my $file = get_path_object_( $last_arg );
    my $cont;
    eval {
        $cont = $encoding_utf8 ? $file->slurp_utf8() : $file->slurp();
    };
    if ( $@ ) {
        my $err = $@;
        $err =~ s/at .+ line \d+//;
        info "$err: failed to execute a programme from a desktop file";
        return false;
    }

    $cont;
}

!!'^^';
