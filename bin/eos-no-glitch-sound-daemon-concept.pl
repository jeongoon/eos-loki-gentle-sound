#!/usr/bin/env perl
# -*- Mode: cperl; cperl-indent-level:4; tab-width: 8; indent-tabs-mode: nil -*-
# -*- coding: utf-8 -*-
# vim: set tabstop 8 expandtab:

# This is part of eos-workaround/no-glitch-sound
# Copyright (c) 2017 JEON Myoungjin <jeongoon@gmail.com>

use 5.012;
use strict; use warnings;
use boolean;
use feature qw(switch);

use POSIX qw(WNOHANG);
use File::Which;
use Fcntl ':flock';
use Time::HiRes qw(sleep);
use File::Which;
use sigtrap handler => handleSigInt => 'INT';
use sigtrap handler => handleSigErr => 'untrapped';

use FindBin;
use File::Spec;

use lib ( map { Cwd::abs_path( File::Spec->catfile( $FindBin::RealBin, @$_ ) ) }
          ( [ qw(.. lib) ], [ ( '..' ) x (3), 'myPerl' ] ) );

use FreeDE::App
  ( -AppName => 'no-glich-sound',
    -Debug   => true,
    -Verbose => true,
    qw(fs app :msg)
  );


package DaemonData;
use Class::Struct;
struct ( PID => '$', playerPID => '$', keepRunning => '$' );

package main;

sub checkChildren;
sub isPlayerAlive;
sub stopPlayer;
sub waitSignal;

use version 0.77; our $VERSION = version->declare( 'v0.0.1' );
info getAppName()." starts normally: version: $VERSION, process number: $$";

my $daemon = DaemonData->new;
dmsg "First fork for starting new session(daemon session)";

$daemon->PID( fork );
# XXX: not sure about return value
defined $daemon->PID or leave "Could not fork";

if ( $daemon->PID != 0 ) {
    info "start a new daemon: exit";
    exit 0;
}

POSIX::setsid() or leave "setsid() failed: unexpected error: $!";

spawn_audio_player:
dmsg "Second fork() for an audio player";
$daemon->playerPID( fork );

if ( not defined $daemon->playerPID ) {
    leave "Could not fork() for player: exit.";
}

$daemon->keepRunning( true );

if ( $daemon->playerPID == 0 ) {
    my $no_sound_file = fs->catfile( app->myHome, 'GoogleDrive', 'Audio', 'test.wav' );
    dmsg "use $no_sound_file to play for opening sound device.";
#    close STDIN;
#    close STDOUT;
#    close STDERR;

    exec ( 'aplay', $no_sound_file );
    # child process never reach here.
    leave "Impossible";
}

$|++;
dmsg "fork() for player is succeed.";
dmsg "wait for 2 sec: this will be enough for player to start playing";
sleep 2;
my $count_sigstop = kill POSIX::SIGSTOP => $daemon->playerPID;
dmsg "Tried to kill: count: $count_sigstop";

manage_daemon:
dmsg "idle until die or caught signal";
waitSignal;

$daemon->keepRunning and goto manage_daemon;

sub waitSignal {
    sleep 1000 while true;
    checkChildren();
}

sub checkChildren {
    dmsg "reaping child process";
    true while waitpid( -1, WNOHANG ) > 0;
    # ref: http://perldoc.perl.org/perlipc.html#Signals
    # FIXME: move to FreeDe::App::pid_is_alive() or something like that.
    if ( not ( kill 0 => $daemon->playerPID or $!{EPERM} ) ) {
        dmsg "player process seems to be dead: trying to spawn another";
        goto spawn_audio_player;
    }
}

sub handleSigInt () {
    dmsg "FIXME: kill previous player and make a new one";
}

sub handleSigErr () {
    my $cnt_sig;
    dmsg "handling other signals except SIGINT";
    stopPlayer;
    exit 100;
}

sub isPlayerAlive () {
    # ref: http://perldoc.perl.org/perlipc.html#Signals
    my $pid = $daemon->playerPID;
    defined $pid and ( ( kill 0 => $pid ) or $!{EPERM} );
}

sub stopPlayer {
    dmsg "if player stopped, make it play again";
    my $pid = $daemon->playerPID;
    my $cnt_sig;
    if ( isPlayerAlive ) {
        $cnt_sig =  kill POSIX::SIGCONT => $pid;
    }

    dmsg "and kill it again.";
    kill POSIX::SIGKILL => $pid;
    isPlayerAlive
      and dmsg "player(PID:$pid) is actually not dead:".
      " player probably become a zombie";
}

exit 0;
