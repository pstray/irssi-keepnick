#
# Copyright (C) 2001 by Peder Stray <peder@ninja.no>
#

use strict;
use Irssi 20011118.1727;
use Irssi::Irc;

# ======[ Variables ]===================================================

my(%keepnick);		# nicks we want to keep
my(%getnick);		# nicks we are currently waiting for
my(%inactive);		# inactive chatnets

# ======[ Helper functions ]============================================

# --------[ check_nick ]------------------------------------------------

sub check_nick {
    my($server,$net,$nick);

    for $net (keys %keepnick) {
	next if $inactive{$net};
	$server = Irssi::server_find_chatnet($net);
	next unless $server;
	next if lc $server->{nick} eq lc $keepnick{$net};

	$getnick{$net} = $keepnick{$net};
    }

    for $net (keys %getnick) {
	$server = Irssi::server_find_chatnet($net);
	next unless $server;
	$nick = $getnick{$net};
	if (lc $server->{nick} eq lc $nick) {
	    delete $getnick{$net};
	    next;
	}
	$server->send_raw("ISON :$nick");
	Irssi::signal_add_first("event 303", "sig_ison");
    }
}

# --------[ save_nicks ]------------------------------------------------

sub save_nicks {
    my($auto) = @_;
    my($file) = Irssi::get_irssi_dir."/keepnick";
    my($count) = 0;
    local(*CONF);

    return if $auto && !Irssi::settings_get_bool('keepnick_autosave');

    open CONF, "> $file";
    for my $net (sort keys %keepnick) {
	print CONF "$net\t$keepnick{$net}\n";
	$count++;
    }
    close CONF;

    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_crap',
		       "Saved $count nicks to $file")
	unless $auto;
}

# --------[ load_nicks ]------------------------------------------------

sub load_nicks {
    my($file) = Irssi::get_irssi_dir."/keepnick";
    my($count) = 0;
    local(*CONF);

    %keepnick = ();
    open CONF, "< $file";
    while (<CONF>) {
	my($net,$nick) = split;
	if ($net && $nick) {
	    $keepnick{$net} = $nick;
	    $count++;
	}
    }
    close CONF;

    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_crap',
		       "Loaded $count nicks from $file");
}

# ======[ Signal Hooks ]================================================

# --------[ sig_ison ]--------------------------------------------------

sub sig_ison {
    my($server,$text) = @_;
    Irssi::signal_remove("event 303", "sig_ison");
    my $nick = $getnick{$server->{chatnet}};
    if ($text !~ /:\Q$nick\E\s?$/i) {
	$server->send_raw("NICK :$nick");
    }
    Irssi::signal_stop();
}

# --------[ sig_quit ]--------------------------------------------------

# if anyone quits, check if we want their nick.
sub sig_quit {
    my($server,$nick) = @_;
    if (lc $nick eq lc $getnick{$server->{chatnet}}) {
	$server->send_raw("NICK :$nick");
    }
}

# --------[ sig_nick ]--------------------------------------------------

# if anyone changes their nick, check if we want their old one.
sub sig_nick {
    my($server,$newnick,$oldnick) = @_;
    if (lc $oldnick eq lc $getnick{$server->{chatnet}}) {
	$server->send_raw("NICK :$oldnick")
    }
}

# --------[ sig_own_nick ]----------------------------------------------

# if we change our nick, check it to see if we wanted it and if so
# remove it from the list.
sub sig_own_nick {
    my($server,$newnick,$oldnick) = @_;
    my($chatnet) = $server->{chatnet};
    if (lc $newnick eq lc $keepnick{$chatnet}) {
	delete $getnick{$chatnet};
	if ($inactive{$chatnet}) {
	    delete $inactive{$chatnet};
	    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_unhold',
			       $chatnet);
	}
    } elsif (lc $oldnick eq lc $keepnick{$chatnet}) {
	$inactive{$chatnet} = 1;
	delete $getnick{$chatnet};
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_hold',
			   $chatnet);
    }
}

# --------[ sig_setup_reread ]------------------------------------------

# main setup is reread, so let us do it too
sub sig_setup_reread {
    load_nicks;
}

# --------[ sig_setup_save ]--------------------------------------------

# main config is saved, and so we should save too
sub sig_setup_save {
    my($mainconf,$auto) = @_;
    save_nicks($auto);
}

# ======[ Commands ]====================================================

# --------[ KEEPNICK ]--------------------------------------------------

# Usage: /KEEPNICK [-net <chatnet>] [<nick>]
sub cmd_keepnick {
    my(@params) = split " ", shift;
    my($server) = @_;
    my($chatnet,$nick,@opts);

    # parse named parameters from the parameterlist
    while (@params) {
	my($param) = shift @params;
	if ($param =~ /^-(chat|irc)?net$/i) {
	    $chatnet = shift @params;
	} elsif ($param =~ /^-/) {
	    Irssi::print("Unknown parameter $param");
	} else {
	    push @opts, $param;
	}
    }
    $nick = shift @opts;

    # check if the ircnet specified (if any) is valid, and if so get the
    # server for it
    if ($chatnet) {
	my($cn) = Irssi::chatnet_find($chatnet);
	unless ($cn) {
	    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_crap',
			       "Unknown chat network: $chatnet");
	    return;
	}
	$chatnet = $cn->{name};
	$server = Irssi::server_find_chatnet($chatnet);
    }

    # if we need a server, check if the one we got is connected.
    unless ($server || ($nick && $chatnet)) {
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_crap',
			   "Not connected to server");
	return;
    }

    # lets get the chatnet, and the nick we want
    $chatnet ||= $server->{chatnet};
    $nick    ||= $server->{nick};

    if ($inactive{$chatnet}) {
	delete $inactive{$chatnet};
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_unhold',
			   $chatnet);
    }

    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_add', $nick,
		       $chatnet);

    $keepnick{$chatnet} = $nick;

    save_nicks(1);
    check_nick();
}

# --------[ UNKEEPNICK ]------------------------------------------------

# Usage: /UNKEEPNICK [<chatnet>]
sub cmd_unkeepnick {
    my($chatnet,$server) = @_;

    # check if the ircnet specified (if any) is valid, and if so get the
    # server for it
    if ($chatnet) {
	my($cn) = Irssi::chatnet_find($chatnet);
	unless ($cn) {
	    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_crap',
			       "Unknown chat network: $chatnet");
	    return;
	}
	$chatnet = $cn->{name};
    } else {
	$chatnet = $server->{chatnet};
    }

    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_remove',
		       $keepnick{$chatnet}, $chatnet);

    delete $keepnick{$chatnet};
    delete $getnick{$chatnet};

    save_nicks(1);
}

# --------[ LISTNICK ]--------------------------------------------------

# Usage: /LISTNICK
sub cmd_listnick {
    my(@nets) = sort { lc $a cmp lc $b } keys %keepnick;
    if (@nets) {
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_list_header');
	for (@nets) {
	    Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_list_line',
			       $keepnick{$_}, $_,
			       $inactive{$_}?'inactive':'active');
	}
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_list_footer');
    } else {
	Irssi::printformat(MSGLEVEL_CLIENTCRAP, 'keepnick_list_empty');
    }
}

# ======[ Setup ]=======================================================

# --------[ Register settings ]-----------------------------------------

Irssi::settings_add_bool('keepnick', 'keepnick_autosave', 1);

# --------[ Register formats ]------------------------------------------

Irssi::theme_register(
[
 'keepnick_crap',
 '{line_start}{hilight Keepnick:} $0',

 'keepnick_add',
 '{line_start}{hilight Keepnick:} Now keeping {nick $0} on [$1]',

 'keepnick_remove',
 '{line_start}{hilight Keepnick:} Stopped trying to keep {nick $0} on [$1]',

 'keepnick_hold',
 '{line_start}{hilight Keepnick:} Nickkeeping deactivated on [$0]',

 'keepnick_unhold',
 '{line_start}{hilight Keepnick:} Nickkeeping reactivated on [$0]',

 'keepnick_list_empty',
 '{line_start}{hilight Keepnick:} No nicks in keep list',

 'keepnick_list_header',
 '',

 'keepnick_list_line',
 '{line_start}{hilight Keepnick:} Keeping {nick $0} in [$1] ($2)',

 'keepnick_list_footer',
 '',
]);

# --------[ Register signals ]------------------------------------------

Irssi::signal_add('message quit', 'sig_quit');
Irssi::signal_add('message nick', 'sig_nick');
Irssi::signal_add('message own_nick', 'sig_own_nick');

Irssi::signal_add('setup saved', 'sig_setup_save');
Irssi::signal_add('setup reread', 'sig_setup_reread');

# --------[ Register commands ]-----------------------------------------

Irssi::command_bind("keepnick", "cmd_keepnick");
Irssi::command_bind("listnick", "cmd_listnick");

# --------[ Register timers ]-------------------------------------------

Irssi::timeout_add(12000, 'check_nick', '');

# --------[ Load config ]-----------------------------------------------

load_nicks;

# ======[ END ]=========================================================

# Local Variables:
# header-initial-hide: t
# mode: header-minor
# end:
