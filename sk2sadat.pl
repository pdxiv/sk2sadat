#!/usr/bin/perl
use strict;
use warnings;
use English qw( -no_match_vars );
use Carp;
use Readonly;
our $VERSION = '0.0.1';

# Constants
Readonly::Scalar my $REALLY_BIG_NUMBER          => 32_767;
Readonly::Scalar my $VERB_AUTO                  => 0;
Readonly::Scalar my $VERB_GO                    => 1;
Readonly::Scalar my $VERB_CARRY                 => 10;
Readonly::Scalar my $VERB_DROP                  => 18;
Readonly::Scalar my $NOUN_ANY                   => 0;
Readonly::Scalar my $NOUN_NORTH                 => 1;
Readonly::Scalar my $NOUN_SOUTH                 => 2;
Readonly::Scalar my $NOUN_EAST                  => 3;
Readonly::Scalar my $NOUN_WEST                  => 4;
Readonly::Scalar my $NOUN_UP                    => 5;
Readonly::Scalar my $NOUN_DOWN                  => 6;
Readonly::Scalar my $INITIAL_DATA_COUNTER_VALUE => -1;
Readonly::Scalar my $TRUE                       => -1;
Readonly::Scalar my $FALSE                      => 0;
Readonly::Scalar my $CARDINAL_DIRECTIONS        => 6;
Readonly::Scalar my $FIELDS_IN_ROOM             => $CARDINAL_DIRECTIONS + 1;
Readonly::Scalar my $FIELDS_IN_ITEM             => 3;
Readonly::Scalar my $LIGHSOURCE_POSITION        => 9;
Readonly::Scalar my $MINIMUM_ITEMS              => $LIGHSOURCE_POSITION + 1;
Readonly::Scalar my $MAXIMUM_ACTION_NOUNS       => 150;
Readonly::Scalar my $MAXIMUM_EVEN_MESSAGES      => 99;
Readonly::Scalar my $CONDITION_MULTIPLIER       => 20;
Readonly::Scalar my $CONDITIONS                 => 5;
Readonly::Scalar my $COMMANDS                   => 4;
Readonly::Scalar my $LOW_MESSAGE_LIMIT          => 51;
Readonly::Scalar my $RESERVED_COMMAND_CODES     => 50;
Readonly::Scalar my $COMMAND_CODE_MULTIPLIER    => 150;

# Commandline flags (not yet implemented)
my $do_not_create_noun_for_item = $FALSE;    # May save space in noun table if terp supports it
my $do_not_concatenate_messages = $FALSE;    # Some advantages, and some disadvantages
my $buckaroo_mode               = $FALSE;    # Concatenate adjacent print messages on the same line

# Initialize ScottKit header values to defaults, excluding "lightsource"
my %scottkit_header = (
    'ident'     => 0,
    'lighttime' => $REALLY_BIG_NUMBER,
    'maxload'   => $REALLY_BIG_NUMBER,
    'start'     => 'nowhere',
    'treasury'  => 'nowhere',
    'unknown1'  => 0,
    'unknown2'  => 0,
    'version'   => 0,
    'wordlen'   => 3,
);

my %command_condition_cost = (
    'get'                   => 1,
    'drop'                  => 1,
    'goto'                  => 1,
    'destroy'               => 1,
    'set_dark'              => 0,
    'clear_dark'            => 0,
    'set_flag'              => 1,
    'destroy2'              => 1,
    'clear_flag'            => 1,
    'die'                   => 0,
    'put'                   => 2,
    'game_over'             => 0,
    'look'                  => 0,
    'score'                 => 0,
    'inventory'             => 0,
    'set_flag0'             => 0,
    'clear_flag0'           => 0,
    'refill_lamp'           => 0,
    'clear'                 => 0,
    'save_game'             => 0,
    'swap'                  => 2,
    'continue'              => 0,
    'superget'              => 1,
    'put_with'              => 2,
    'look2'                 => 0,
    'dec_counter'           => 0,
    'print_counter'         => 0,
    'set_counter'           => 1,
    'swap_room'             => 0,
    'select_counter'        => 1,
    'add_to_counter'        => 1,
    'subtract_from_counter' => 1,
    'print_noun'            => 0,
    'println_noun'          => 0,
    'println'               => 0,
    'swap_specific_room'    => 1,
    'pause'                 => 0,
    'draw'                  => 1,
    'print'                 => 0,
    'comment'               => 0,
    'no_operation'          => 0,
);

my @scottkit_action;
my @scottkit_action_comment;
my @scottkit_room;
my %scottkit_verbgroup;
my %scottkit_noungroup;
my @scottkit_item;

my @final_verb;
my @final_noun;
my @final_room;
my @final_item;
my @final_message;
my @final_action;
my @final_header;
my $wordlength;

parse_scottkit_data();

move_lightsource();    # Necessary if an item has been explicitly defined as a light source

populate_vocabulary();
populate_room();
populate_item();

if ( !$do_not_concatenate_messages ) {
    foreach (@scottkit_action) {
        defragment_print_in_command( ${$_}{command} );
    }
}

extend_long_actions();

move_print_even_to_odd();

populate_messages();

populate_action();

populate_header();

print_dat_data();

sub defragment_print_in_command {
    my $string_join_character;
    if ($buckaroo_mode) {
        $string_join_character = q{ };
    }
    else {
        $string_join_character = "\n";
    }
    my %no_swap_with_print = (
        die           => q{},
        game_over     => q{},
        inventory     => q{},
        look          => q{},
        look2         => q{},
        pause         => q{},
        print_noun    => q{},
        println       => q{},
        print_counter => q{},
        println_noun  => q{},
        score         => q{},
    );
    my $command = shift;

    # Find "print" commands and concatenate with "println" and "print" commands
    for my $command_index ( reverse 0 .. scalar @{$command} - 1 ) {
        if ( ${$command}[$command_index]{code} eq 'print' ) {
            for my $search_index ( reverse 0 .. $command_index - 1 ) {
                my $found_code = ${$command}[$search_index]{code};
                if ( $found_code eq 'print' ) {
                    ${$command}[$search_index]{argument_1} .=
                      $string_join_character . ${$command}[$command_index]{argument_1};
                    splice @{$command}, $command_index, 1;
                    last;
                }
                if ( $found_code eq 'println' ) {
                    ${$command}[$search_index]{argument_1} = "\n${$command}[$command_index]{argument_1}";
                    ${$command}[$search_index]{code}       = 'print';
                    splice @{$command}, $command_index, 1;
                    last;
                }
                if ( exists $no_swap_with_print{$found_code} ) {
                    last;
                }
            }
        }
    }

    # Find and concatenate "println" commands with "print" commands
    # Find number of "println" in command
    my $number_of_println = 0;
    for my $command_index ( reverse 0 .. scalar @{$command} - 1 ) {
        if ( ${$command}[$command_index]{code} eq 'println' ) { $number_of_println++; }
    }

    # Repeat until all println resolved
    for ( 1 .. $number_of_println ) {
        for my $command_index ( reverse 0 .. scalar @{$command} - 1 ) {
            if ( ${$command}[$command_index]{code} eq 'println' ) {
                for my $search_index ( reverse 0 .. $command_index - 1 ) {
                    my $found_code = ${$command}[$search_index]{code};
                    if ( $found_code eq 'print' ) {
                        ${$command}[$search_index]{argument_1} .= "\n";
                        splice @{$command}, $command_index, 1;
                        last;
                    }
                    if ( exists $no_swap_with_print{$found_code} ) {
                        last;
                    }
                }
            }
        }
    }
}

sub extend_long_actions {
    for my $action_index ( reverse 0 .. scalar @scottkit_action - 1 ) {
        if ( action_needs_to_be_extended($action_index) ) {
            extend_action($action_index);
        }
    }
    return 1;
}

sub extend_action {
    my $action_index       = shift;
    my $original_condition = $scottkit_action[$action_index]{condition};
    my $original_command   = $scottkit_action[$action_index]{command};
    my @extended_action;
    my $extended_counter = 0;

    # Remove any existing continue commands, and add our own.
    for my $command_index ( reverse 0 .. scalar @{$original_command} - 1 ) {
        my $code = ${$original_command}[$command_index]{code};
        if ( $code eq 'continue' ) {
            splice @{$original_command}, $command_index, 1;
        }
    }

    # Inherit properties from the original action on the first extended action
    $extended_action[$extended_counter]{verb}      = $scottkit_action[$action_index]{verb};
    $extended_action[$extended_counter]{noun}      = $scottkit_action[$action_index]{noun};
    $extended_action[$extended_counter]{type}      = $scottkit_action[$action_index]{type};
    $extended_action[$extended_counter]{line}      = $scottkit_action[$action_index]{line};
    $extended_action[$extended_counter]{condition} = [];
    $extended_action[$extended_counter]{command}   = [];
    foreach ( @{$original_condition} ) {
        my %condition = ( 'code' => ${$_}{code}, 'argument' => ${$_}{argument} );
        push @{ $extended_action[$extended_counter]{condition} }, \%condition;
    }
    my %command = ( 'code' => 'continue', 'argument_1' => q{}, 'argument_2' => q{} );
    push @{ $extended_action[$extended_counter]{command} }, \%command;

    # Push commands to extended actions
    while ( scalar @{ $scottkit_action[$action_index]{command} } > 0 ) {
        my $command_to_move      = shift @{ $scottkit_action[$action_index]{command} };
        my $condition_space_left = $CONDITIONS - conditions_in_action( $extended_action[$extended_counter] );
        my $command_space_left   = $COMMANDS - commands_in_action( $extended_action[$extended_counter] );
        my $condition_cost       = $command_condition_cost{ $$command_to_move{code} };

        # Create a new action if we've run out of space in condition slots or command slots
        if ( ( $command_space_left == 0 ) || ( $condition_cost > $condition_space_left ) ) {
            $extended_counter++;
            $extended_action[$extended_counter]{verb}      = 0;
            $extended_action[$extended_counter]{noun}      = 0;
            $extended_action[$extended_counter]{type}      = 'occur';
            $extended_action[$extended_counter]{line}      = $scottkit_action[$action_index]{line};
            $extended_action[$extended_counter]{condition} = [];
            $extended_action[$extended_counter]{command}   = [];
        }
        push @{ $extended_action[$extended_counter]{command} }, $command_to_move;
    }

    # Insert extended actions in the place of the old long action
    splice @scottkit_action, $action_index, 1, @extended_action;

    # Duplicate action comment to new extended actions
    my $action_comment = $scottkit_action_comment[$action_index];
    my @comment_list = ( ($action_comment) x ( scalar @extended_action ) );
    splice @scottkit_action_comment, $action_index, 1, @comment_list;
}

sub conditions_in_action {
    my $action            = shift;
    my $condition_counter = scalar @{ ${$action}{condition} };
    foreach my $commmand_instance ( @{ ${$action}{command} } ) {
        my $code = ${$commmand_instance}{code};
        $condition_counter += $command_condition_cost{$code};
    }
    return $condition_counter;
}

sub commands_in_action {
    my $action          = shift;
    my $command_counter = scalar @{ ${$action}{command} };
}

sub action_needs_to_be_extended {
    my $action_index         = shift;
    my $condition_score      = 0;
    my $base_condition_score = 0;
    my $command_score        = 0;
    my $command              = $scottkit_action[$action_index]{command};
    my $condition            = $scottkit_action[$action_index]{condition};

    $condition_score = scalar @{$condition};
    $base_condition_score += $condition_score;

    # Check that number of "base conditions" doesn't exceed the limit of 5.
    if ( $base_condition_score > $CONDITIONS ) {
        print STDERR 'ERROR: Too many condition entries ('
          . $base_condition_score . q{/}
          . $CONDITIONS
          . ') in action on line '
          . $scottkit_action[$action_index]{line}
          . ". Please consider splitting into subactions or reducing complexity.\n";
        exit 1;
    }

    foreach ( @{$command} ) {
        my $command_code = ${$_}{code};
        $command_score++;
        $condition_score += $command_condition_cost{$command_code};
    }

    if ( $condition_score > $CONDITIONS or $command_score > $COMMANDS ) {
        return $TRUE;
    }
    return $FALSE;
}

sub print_dat_data {

    # Header
    foreach (@final_header) {
        print "$_\n";
    }

    # Actions
    foreach (@final_action) {
        foreach ( @{$_} ) {
            print "$_\n";
        }
    }

    # Vocabulary
    my $number_of_verbs = scalar @final_verb - 1;
    my $number_of_nouns = scalar @final_noun - 1;
    if ( $number_of_verbs > $number_of_nouns ) {
        my @empty = map '', ( 1 .. ( $number_of_verbs - $number_of_nouns ) );
        push @final_noun, @empty;

    }
    elsif ( $number_of_nouns > $number_of_verbs ) {
        my @empty = map '', ( 1 .. ( $number_of_nouns - $number_of_verbs ) );
        push @final_verb, @empty;
    }
    for ( 0 .. scalar @final_verb - 1 ) {
        print q{"} . $final_verb[$_] . q{"} . "\n";
        print q{"} . $final_noun[$_] . q{"} . "\n";
    }

    # Room
    foreach (@final_room) {
        print "$_\n";
    }

    # Message
    foreach (@final_message) {
        print "\"$_\"\n";
    }

    # Items
    foreach my $item_field (@final_item) {
        my $message_text = $$item_field[0];
        if ( defined $$item_field[1] ) {
            $message_text .= q{/} . $$item_field[1] . q{/};
        }
        print "\"$message_text\" $$item_field[2]\n";
    }

    # Action comments
    foreach (@scottkit_action_comment) {
        s/^"([\S\s]*)"$/$1/;
        s/^([\S\s]*)$/"$1"/;
        print "$_\n";
    }

    # Footer
    print "$scottkit_header{version}\n";
    print "$scottkit_header{ident}\n";

    # Attempt to calculate checksum: (2*#actions + #objects + version)
    my $checksum = ( 2 * scalar @scottkit_action ) + ( scalar @final_item ) + $scottkit_header{version};
    print "$checksum\n";
}

sub populate_header {

    # Number of bytes. Not yet implemented.
    push @final_header, $REALLY_BIG_NUMBER;

    # Number of items. This should be increased by 1 if compatibility with official TRS-80 interpreter is desired.
    push @final_header, scalar @final_item - 1;

    # Number of actions.
    push @final_header, scalar @final_action - 1;

    # Number of vocabulary entries
    my $number_of_verbs = scalar @final_verb - 1;
    my $number_of_nouns = scalar @final_noun - 1;
    if ( $number_of_verbs >= $number_of_nouns ) {
        push @final_header, $number_of_verbs;
    }
    else {
        push @final_header, $number_of_nouns;
    }

    # Number of rooms
    push @final_header, ( scalar @final_room ) / 7 - 1;

    # Maximum carried objects
    push @final_header, $scottkit_header{maxload};

    # Starting room
    my $found_starting_room;
    my $starting_room_index = 0;
    foreach (@scottkit_room) {
        if ( ${$_}{id} eq $scottkit_header{start} ) {
            $found_starting_room = $starting_room_index - 1;
        }
        $starting_room_index++;
    }
    if ( !defined $found_starting_room ) {
        print STDERR 'ERROR: Starting room with id "' . $scottkit_header{start} . "\" not found.\n";
        exit 1;
    }
    push @final_header, $found_starting_room;

    # Number of treasures
    my $treasure_counter = 0;
    foreach my $derp (@final_item) {
        if ( ( substr $$derp[0], 0, 1 ) eq q{*} ) { $treasure_counter++; }
    }
    push @final_header, $treasure_counter;

    # Word length
    push @final_header, $scottkit_header{wordlen};

    # Time limit
    push @final_header, $scottkit_header{lighttime};

    # Number of messages
    push @final_header, scalar @final_message - 1;

    # Treasure room number
    my $found_treasure_room;
    my $treasure_room_index = 0;
    foreach (@scottkit_room) {
        if ( ${$_}{id} eq $scottkit_header{treasury} ) {
            $found_treasure_room = $treasure_room_index - 1;
        }
        $treasure_room_index++;
    }
    if ( !defined $found_treasure_room ) {
        print STDERR 'ERROR: Treasury room with id "' . $scottkit_header{treasury} . "\" not found.\n";
        exit 1;
    }
    push @final_header, $found_treasure_room;
}

sub populate_messages {
    my %low_message;     # Limited to 99 entries. Used by "even" print commands
    my %high_message;    # Unlimited, disregarding interpreter implementation
    my $action_index = 0;
    foreach my $current_action (@scottkit_action) {
        my $current_commands = ${$current_action}{command};
        my $command_index    = 0;
        foreach my $commands ( @{$current_commands} ) {
            if ( ${$commands}{code} eq 'print' ) {
                if ( ( $command_index % 2 ) == 1 ) {
                    $low_message{ ${$commands}{argument_1} } = q{};
                }
                else {
                    $high_message{ ${$commands}{argument_1} } = q{};
                }
            }
            $command_index++;
        }
        $action_index++;
    }

    # Remove high messages that are present in low messages list
    foreach my $message_text ( keys %high_message ) {
        if ( exists $low_message{$message_text} ) {
            delete $high_message{$message_text};
        }
    }

    my $number_of_low_messages = scalar keys %low_message;
    if ( $number_of_low_messages > $MAXIMUM_EVEN_MESSAGES ) {
        print STDERR 'ERROR: Maximum number of "even" messages used in actions ('
          . $number_of_low_messages
          . ') exceeds maximum ('
          . $MAXIMUM_EVEN_MESSAGES . '). '
          . "Please consider reducing the number of messages or splitting actions into subactions.\n";
        exit 1;
    }
    foreach ( sort keys %low_message ) {
        push @final_message, $_;
    }
    foreach ( sort keys %high_message ) {
        push @final_message, $_;
    }
    unshift @final_message, q{};
}

# This subroutine should attempt to move print commands in actions from "even" positions
# to "odd" positions, since even "print commands" are limited to 99 messages.
# This requires the addition of a "no_operation" command
# Print commands with command index 1 and 3 are bad, since this wastes space in the message table.
# They should be swapped with other commands with index 0 and 2, if possible!
sub move_print_even_to_odd {

    # Print "commands"can be swapped with any other commands, except the following
    my %no_swap_with_print = (
        die           => q{},
        game_over     => q{},
        inventory     => q{},
        look          => q{},
        look2         => q{},
        pause         => q{},
        print         => q{},
        print_noun    => q{},
        println       => q{},
        print_counter => q{},
        println_noun  => q{},
        score         => q{},
    );

    # Pad unused command slots with "no_operation"
    foreach my $current_action (@scottkit_action) {
        my $current_commands = ${$current_action}{command};
        my $noop_to_add      = $COMMANDS - scalar @{$current_commands};
        for ( 1 .. $noop_to_add ) {
            my %noop_data = (
                'code'       => 'no_operation',
                'argument_1' => q{},
                'argument_2' => q{},
            );
            push @{$current_commands}, \%noop_data;
        }
    }

    foreach my $current_action (@scottkit_action) {
        my $current_commands = ${$current_action}{command};

        # Attempt to swap print command with index 1 with index 0
        if ( ${$current_commands}[1]{code} eq 'print' ) {
            if ( !exists $no_swap_with_print{ ${$current_commands}[0]{code} } ) {
                my $temp_command_data = ${$current_commands}[0];
                ${$current_commands}[0] = ${$current_commands}[1];
                ${$current_commands}[1] = $temp_command_data;
            }
        }

        # Attempt to swap print command with index 3 with index 2
        if ( ${$current_commands}[3]{code} eq 'print' ) {
            if ( !exists $no_swap_with_print{ ${$current_commands}[2]{code} } ) {
                my $temp_command_data = ${$current_commands}[2];
                ${$current_commands}[2] = ${$current_commands}[3];
                ${$current_commands}[3] = $temp_command_data;
            }
        }
    }
}

sub print_action_commands {
    my $action_index = 0;
    foreach my $current_action (@scottkit_action) {
        my $current_commands = ${$current_action}{command};
        my $command_index    = 0;
        foreach my $commands ( @{$current_commands} ) {
            print 'DEBUG: ';
            if ( ${$commands}{code} eq 'print' and ( $command_index % 2 ) == 1 ) {
                print '* ';
            }
            print "$action_index $command_index: $$commands{code}\n";

            $command_index++;
        }
        $action_index++;
    }
}

sub populate_action {
    my %condition_data = (
        'param'      => [ 0,  'none' ],
        'carried'    => [ 1,  'item' ],
        'here'       => [ 2,  'item' ],
        'present'    => [ 3,  'item' ],
        'at'         => [ 4,  'room' ],
        '!here'      => [ 5,  'item' ],
        '!carried'   => [ 6,  'item' ],
        '!at'        => [ 7,  'room' ],
        'flag'       => [ 8,  'number' ],
        '!flag'      => [ 9,  'number' ],
        'loaded'     => [ 10, 'none' ],
        '!loaded'    => [ 11, 'none' ],
        '!present'   => [ 12, 'item' ],
        'exists'     => [ 13, 'item' ],
        '!exists'    => [ 14, 'item' ],
        'counter_le' => [ 15, 'number' ],
        'counter_gt' => [ 16, 'number' ],
        '!moved'     => [ 17, 'item' ],
        'moved'      => [ 18, 'item' ],
        'counter_eq' => [ 19, 'number' ],
    );

    my %command_data = (
        'get'                   => [ 52, 'item',   'none' ],
        'drop'                  => [ 53, 'item',   'none' ],
        'goto'                  => [ 54, 'room',   'none' ],
        'destroy'               => [ 55, 'item',   'none' ],
        'set_dark'              => [ 56, 'none',   'none' ],
        'clear_dark'            => [ 57, 'none',   'none' ],
        'set_flag'              => [ 58, 'number', 'none' ],
        'destroy2'              => [ 59, 'item',   'none' ],
        'clear_flag'            => [ 60, 'number', 'none' ],
        'die'                   => [ 61, 'none',   'none' ],
        'put'                   => [ 62, 'item',   'room' ],
        'game_over'             => [ 63, 'none',   'none' ],
        'look'                  => [ 64, 'none',   'none' ],
        'score'                 => [ 65, 'none',   'none' ],
        'inventory'             => [ 66, 'none',   'none' ],
        'set_flag0'             => [ 67, 'none',   'none' ],
        'clear_flag0'           => [ 68, 'none',   'none' ],
        'refill_lamp'           => [ 69, 'none',   'none' ],
        'clear'                 => [ 70, 'none',   'none' ],
        'save_game'             => [ 71, 'none',   'none' ],
        'swap'                  => [ 72, 'item',   'item' ],
        'continue'              => [ 73, 'none',   'none' ],
        'superget'              => [ 74, 'item',   'none' ],
        'put_with'              => [ 75, 'item',   'item' ],
        'look2'                 => [ 76, 'none',   'none' ],
        'dec_counter'           => [ 77, 'none',   'none' ],
        'print_counter'         => [ 78, 'none',   'none' ],
        'set_counter'           => [ 79, 'number', 'none' ],
        'swap_room'             => [ 80, 'none',   'none' ],
        'select_counter'        => [ 81, 'number', 'none' ],
        'add_to_counter'        => [ 82, 'number', 'none' ],
        'subtract_from_counter' => [ 83, 'number', 'none' ],
        'print_noun'            => [ 84, 'none',   'none' ],
        'println_noun'          => [ 85, 'none',   'none' ],
        'println'               => [ 86, 'none',   'none' ],
        'swap_specific_room'    => [ 87, 'number', 'none' ],
        'pause'                 => [ 88, 'none',   'none' ],
        'draw'                  => [ 89, 'number', 'none' ],
        'print'                 => [ 0,  'none',   'none' ],
        'comment'               => [ 0,  'none',   'none' ],
        'no_operation'          => [ 0,  'none',   'none' ],
    );

    my @occur_action;
    my @word_action;
    my $current_action_type = 'occur';

    foreach my $action_instance (@scottkit_action) {
        my @current_action_data;
        my $verb;
        my $noun;

        if ( ${$action_instance}{type} eq 'word' ) {
            $verb = find_word_position_in_table( ${$action_instance}{verb}, \@final_verb );
            $noun = find_word_position_in_table( ${$action_instance}{noun}, \@final_noun );
        }
        else {
            $verb = ${$action_instance}{verb};
            $noun = ${$action_instance}{noun};
        }
        if ( $verb == 0 and $noun > 0 ) {
            $current_action_type = 'occur';
        }
        if ( $verb > 0 ) {
            $current_action_type = 'word';
        }

        push @current_action_data, 150 * $verb + $noun;

        my @condition_block;
        my @command_block;

        # Populate "normal" conditions
        foreach my $current_condition ( @{ ${$action_instance}{condition} } ) {
            my $code           = ${$current_condition}{code};
            my $argument       = ${$current_condition}{argument};
            my $code_numeric   = $condition_data{$code}[0];
            my $code_data_type = $condition_data{$code}[1];

            my $encoded_condition =
              $CONDITION_MULTIPLIER * find_index_of_data( $code_data_type, $argument, ${$action_instance}{line} ) +
              $code_numeric;
            push @condition_block, $encoded_condition;
        }

        # Populate "parameter" conditions
        foreach my $current_command ( @{ ${$action_instance}{command} } ) {
            my $code       = ${$current_command}{code};
            my $argument_1 = ${$current_command}{argument_1};
            my $argument_2 = ${$current_command}{argument_2};

            my $code_numeric     = $command_data{$code}[0];
            my $code_data_type_1 = $command_data{$code}[1];
            my $code_data_type_2 = $command_data{$code}[2];

            if ( !defined $code_data_type_1 ) { print "DEBUG: code: $code\n"; }

            if ( $code_data_type_1 ne 'none' ) {
                my $encoded_condition = $CONDITION_MULTIPLIER *
                  find_index_of_data( $code_data_type_1, $argument_1, ${$action_instance}{line} );
                push @condition_block, $encoded_condition;
            }
            if ( $code_data_type_2 ne 'none' ) {
                my $encoded_condition = $CONDITION_MULTIPLIER *
                  find_index_of_data( $code_data_type_2, $argument_2, ${$action_instance}{line} );
                push @condition_block, $encoded_condition;
            }
        }

        my $conditions_in_block = scalar @condition_block;
        if ( $conditions_in_block > $CONDITIONS ) {
            print STDERR 'ERROR: Too many condition entries ('
              . $conditions_in_block . '/'
              . $CONDITIONS
              . ') in action on line '
              . ${$action_instance}{line}
              . ". Please consider splitting into subactions or reducing complexity.\n";
            exit 1;
        }

        # Pad remaining unused condition block slots with zero values
        for ( $conditions_in_block .. $CONDITIONS - 1 ) { push @condition_block, 0; }

        push @current_action_data, (@condition_block);

        # Populate commands (still needs work)
        foreach my $current_command ( @{ ${$action_instance}{command} } ) {
            my $code         = ${$current_command}{code};
            my $code_numeric = $command_data{$code}[0];

            if ( $code ne 'print' ) { push @command_block, $code_numeric; }
            else {
                my $string_to_print = ${$current_command}{argument_1};
                my $found_index;
                for my $message_index ( 1 .. scalar @final_message - 1 ) {
                    if ( $string_to_print eq $final_message[$message_index] ) {
                        $found_index = $message_index;
                        last;
                    }
                }
                if ( $found_index > $LOW_MESSAGE_LIMIT ) {
                    $found_index += $RESERVED_COMMAND_CODES;
                }
                push @command_block, $found_index;
            }
        }

        my $commands_in_block = scalar @command_block;

        if ( $commands_in_block > $COMMANDS ) {
            print STDERR 'ERROR: Too many command entries ('
              . $commands_in_block . '/'
              . $COMMANDS
              . ') in action on line '
              . ${$action_instance}{line}
              . ". Please consider splitting into subactions or reducing complexity.\n";
            exit 1;
        }

        # Pad remaining unused command block slots with zero values
        for ( $commands_in_block .. $COMMANDS - 1 ) { push @command_block, 0; }

        push @current_action_data, $COMMAND_CODE_MULTIPLIER * $command_block[0] + $command_block[1];
        push @current_action_data, $COMMAND_CODE_MULTIPLIER * $command_block[2] + $command_block[3];

        # After preconditions, conditions and commands are done, push to relevant action list
        if ( $current_action_type eq 'occur' ) { push @occur_action, \@current_action_data; }
        if ( $current_action_type eq 'word' )  { push @word_action,  \@current_action_data; }
    }

    # Push to final action data, starting with "occur actions", since some terps need this.
    push @final_action, @occur_action;
    push @final_action, @word_action;
}

sub find_index_of_data {
    my $data_type    = shift;
    my $data_to_find = shift;
    my $action_line  = shift;
    if ( $data_type eq 'item' ) {
        my $item_index = 0;
        foreach my $instance (@scottkit_item) {
            my $item_id = $$instance{id};
            if ( $data_to_find eq $item_id ) {
                return $item_index;
            }
            $item_index++;
        }
        print STDERR 'ERROR: unable to find item "' . $data_to_find . "\" in action on line $action_line\n";
        exit 1;
    }
    if ( $data_type eq 'none' ) {
        return 0;
    }
    if ( $data_type eq 'number' ) {
        return $data_to_find;
    }
    if ( $data_type eq 'room' ) {
        my $room_index = 0;
        foreach my $instance (@scottkit_room) {
            my $room_id = $$instance{id};
            if ( $data_to_find eq $room_id ) {

                # Room index -1 because inventory room "carried" will be removed later
                return $room_index - 1;
            }
            $room_index++;
        }
        print STDERR 'ERROR: unable to find room "' . $data_to_find . "\" in action on line $action_line\n";
        exit 1;
    }
}

sub find_word_position_in_table {
    my $word_to_find    = shift;
    my $table_to_search = shift;

    $word_to_find =~ s/^"|"$//g;
    $word_to_find = uc substr $word_to_find, 0, $wordlength;

    for my $index ( 0 .. scalar @{$table_to_search} - 1 ) {
        if ( $word_to_find eq ${$table_to_search}[$index] ) {
            return $index;
        }
    }
}

sub move_lightsource {

    # If designated lightsource item has been defined, move to the correct slot (9)
    if ( exists $scottkit_header{lightsource} ) {

        # We need a minimum of 10 items, to be able to designate a light source
        my $number_of_items = scalar @scottkit_item;
        if ( $number_of_items < $MINIMUM_ITEMS ) {
            for ( 1 .. $MINIMUM_ITEMS - $number_of_items ) {
                my %dummy_item = ( 'description' => q{}, 'line' => 0, 'room' => 'nowhere', 'id' => random_string(8) );
                push @scottkit_item, \%dummy_item;
            }
        }

        my $current_item_index = 0;
        foreach my $current_item_data (@scottkit_item) {
            if ( $scottkit_header{lightsource} eq ${$current_item_data}{id} ) {
                last;
            }
            $current_item_index++;
        }
        if ( $current_item_index == scalar @scottkit_item ) {
            print STDERR 'ERROR: Unable to find item with ID "'
              . $scottkit_header{lightsource}
              . "\" for lightsource\n";
            exit 1;
        }
        my $lightsource_found_at = $current_item_index;
        my $temporary_item       = $scottkit_item[$LIGHSOURCE_POSITION];
        $scottkit_item[$LIGHSOURCE_POSITION]  = $scottkit_item[$lightsource_found_at];
        $scottkit_item[$lightsource_found_at] = $temporary_item;
    }
}

sub random_string {
    my $number_of_characters = shift;
    my @letters              = ( 'A' .. 'Z' );
    my $output               = q{};
    for ( 1 .. $number_of_characters ) {
        $output .= $letters[ int( rand( scalar @letters ) ) ];
    }
    return $output;
}

sub populate_item {
    $wordlength = $scottkit_header{wordlen};
    foreach my $instance (@scottkit_item) {
        my @final_item_data;
        my $description = ${$instance}{description};
        $description =~ s/^"|"$//sxg;    # Remove quotes around room description
        push @final_item_data, $description;
        my $noun;
        if ( exists ${$instance}{noun} ) {
            $noun = ${$instance}{noun};
            $noun = uc substr $noun, 0, $wordlength;
        }
        push @final_item_data, $noun;
        my $target_room_id = ${$instance}{room};
        my $found          = $FALSE;
        my $room_index     = 0;
        foreach my $room_instance (@scottkit_room) {
            my $id = ${$room_instance}{id};
            if ( $target_room_id eq $id ) {
                push @final_item_data, $room_index - 1;
                $found = $TRUE;
                last;
            }
            $room_index++;
        }
        if ( !$found ) {
            print STDERR 'ERROR: Unable to find room ID "'
              . $target_room_id
              . '" for location in item declaration on line '
              . ${$instance}{line} . ".\n";
            exit 1;
        }
        push @final_item, \@final_item_data;
    }
}

sub populate_room {
    my @direction_id = qw{north south east west up down};
    my $room_index   = 0;
    foreach my $room (@scottkit_room) {
        my @final_room_data;
        my $description = ${$room}{description};
        $description =~ s/^"|"$//sxg;    # Remove quotes around room description

        # Process all the exits
        for my $direction_index ( 0 .. $CARDINAL_DIRECTIONS - 1 ) {
            my $direction_id_word = $direction_id[$direction_index];

            if ( exists ${$room}{exit}{$direction_id_word} ) {
                my $found = $FALSE;
                foreach my $destination_room_index ( 0 .. scalar @scottkit_room - 1 ) {
                    if ( ${$room}{exit}{$direction_id_word} eq $scottkit_room[$destination_room_index]{id} ) {
                        push @final_room_data, $destination_room_index - 1;
                        $found = $TRUE;
                        last;
                    }
                }
                if ( !$found ) {
                    print 'ERROR: unable to find ID "'
                      . ${$room}{exit}{$direction_id_word}
                      . '" for exit in room declaration on line '
                      . ${$room}{line} . ".\n";
                    exit 1;
                }
            }
            else {
                push @final_room_data, 0;
            }
        }

        # Populate all rooms except "inventory room"
        if ( $room_index > 0 ) {
            push @final_room_data, q{"} . $description . q{"};
            push @final_room,      @final_room_data;
        }
        $room_index++;
    }
}

sub populate_vocabulary {
    my $word_pattern        = qr/[\w-]+/i;
    my $quoted_word_pattern = qr/^"($word_pattern)"$/i;
    $wordlength = $scottkit_header{wordlen};
    my ( %unique_verb, %unique_action_noun, %unique_item_noun );

    # Add predefined verbs and nouns
    my @predefined_verb = qw(AUTO GO GET DROP);
    my @predefined_noun = qw(ANY NORTH SOUTH EAST WEST UP DOWN);

    foreach my $verb (@predefined_verb) {
        my $truncated_verb = uc substr $verb, 0, $wordlength;
        $unique_verb{$truncated_verb} = [];
    }
    foreach my $noun (@predefined_noun) {
        my $truncated_noun = uc substr $noun, 0, $wordlength;
        $unique_action_noun{$truncated_noun} = [];
    }

    # Add unique verbs and nouns from actions
    foreach my $action_instance (@scottkit_action) {
        foreach my $action_instance_key ( sort keys %{$action_instance} ) {
            my $word = ${$action_instance}{$action_instance_key};
            if ( $word =~ /$quoted_word_pattern/sx ) {
                my $truncated_word = uc substr $1, 0, $wordlength;
                if ( $action_instance_key eq 'verb' ) {
                    $unique_verb{$truncated_word} = [];
                }
                if ( $action_instance_key eq 'noun' ) {
                    $unique_action_noun{$truncated_word} = [];
                }
            }
        }
    }

    # Add unique nouns from items, unless already defined by actions.
    if ( !$do_not_create_noun_for_item ) {
        foreach my $item_instance (@scottkit_item) {
            foreach ( sort keys %{$item_instance} ) {
                if ( $_ eq 'noun' ) {
                    my $truncated_word = uc substr ${$item_instance}{$_}, 0, $wordlength;
                    if ( !exists $unique_action_noun{$truncated_word} ) {
                        $unique_item_noun{$truncated_word} = [];
                    }
                }
            }
        }
    }

    add_synonym_to_words( \%scottkit_verbgroup, \%unique_verb );
    add_synonym_to_words( \%scottkit_noungroup, \%unique_action_noun );

    # First we need to populate "hard coded" verbs and nouns.
    # Put unique words into final lists
    my @predefined_verb_index = ( $VERB_AUTO, $VERB_GO, $VERB_CARRY, $VERB_DROP );
    my @predefined_noun_index = ( $NOUN_ANY, $NOUN_NORTH, $NOUN_SOUTH, $NOUN_EAST, $NOUN_WEST, $NOUN_UP, $NOUN_DOWN );

    populate_predefined_words( \@predefined_verb, \@predefined_verb_index, \%unique_verb,        \@final_verb );
    populate_predefined_words( \@predefined_noun, \@predefined_noun_index, \%unique_action_noun, \@final_noun );

    # Next, we need to add the "normal" verbs and nouns. This should be done in places in the final word list
    # that are not already occupied.
    put_unique_in_final_word_list_with_synonyms( \%unique_verb,        \@final_verb );
    put_unique_in_final_word_list_with_synonyms( \%unique_action_noun, \@final_noun );

    if ( scalar @final_noun > $MAXIMUM_ACTION_NOUNS ) {
        print STDERR "ERROR: Number of nouns used by actions exceeds $MAXIMUM_ACTION_NOUNS. Please remove "
          . ( scalar @final_noun - $MAXIMUM_ACTION_NOUNS )
          . " noun(s) and/or noun synonym(s).\n";
        exit 1;
    }

    put_unique_in_final_word_list_with_synonyms( \%unique_item_noun, \@final_noun );

    fill_undefined_words_with_blank_string( \@final_verb );
    fill_undefined_words_with_blank_string( \@final_noun );
}

# Add synonyms to verbs and nouns
sub add_synonym_to_words {
    my $scottkit_wordgroup = shift;
    my $unique_word        = shift;

    my $word_pattern        = qr/[\w-]+/i;
    my $quoted_word_pattern = qr/^"($word_pattern)"$/i;
    foreach my $wordgroup_instance ( sort keys %{$scottkit_wordgroup} ) {
        my $synonym      = ${$scottkit_wordgroup}{$wordgroup_instance}{synonym};
        my $primary_word = $wordgroup_instance;
        $primary_word =~ s/$quoted_word_pattern/$1/sx;
        $primary_word = uc substr $primary_word, 0, $wordlength;

        # Silently drop synonym declarations that don't refer to an existing word
        if ( exists ${$unique_word}{$primary_word} ) {
            foreach my $word ( @{$synonym} ) {
                $word =~ s/$quoted_word_pattern/$1/sx;

                # Silently drop synonyms that don't contain valid word characters
                if ( $word =~ /$word_pattern/sx ) {
                    $word = uc substr $word, 0, $wordlength;
                    push @{ ${$unique_word}{$primary_word} }, $word;
                }
            }
        }
    }
}

sub fill_undefined_words_with_blank_string {
    my $final_word = shift;

    # Fill any undefined word entries with blank strings
    foreach ( @{$final_word} ) {
        if ( !defined ) { $_ = q{}; }
    }
}

sub put_unique_in_final_word_list_with_synonyms {
    my $unique_word = shift;
    my $final_word  = shift;
    foreach my $root_word ( sort keys %{$unique_word} ) {
        my $word_entries = scalar @{ ${$unique_word}{$root_word} } + 1;
        my @word_hole    = find_word_list_hole($final_word);
        for my $hole_entry ( 0 .. ( scalar @word_hole / 2 - 1 ) ) {
            my $hole_index = $word_hole[ $hole_entry * 2 ];
            my $hole_size  = $word_hole[ $hole_entry * 2 + 1 ];
            if ( $hole_size >= $word_entries ) {
                populate_words_at_position( $final_word, $hole_index, $root_word, $unique_word, );
                last;
            }
        }
    }
}

sub find_word_list_hole {
    my $unique_word = shift;
    my @found_hole;
    my $undefined_index   = 0;
    my $undefined_counter = 0;
    my $list_index        = 0;
    foreach ( @{$unique_word} ) {
        if (defined) {
            if ( $undefined_counter > 0 ) {
                push @found_hole, ( $undefined_index, $undefined_counter );
                $undefined_counter = 0;
            }
        }
        else {
            $undefined_counter++;
            if ( $undefined_counter == 1 ) {
                $undefined_index = $list_index;
            }
        }
        $list_index++;
    }

    # Add a "really big" hole at the end (since we can add anything there)
    push @found_hole, ( scalar @{$unique_word}, $REALLY_BIG_NUMBER );
    return @found_hole;
}

sub populate_predefined_words {
    my $predefined_word       = shift;
    my $predefined_word_index = shift;
    my $unique_word           = shift;
    my $final_word            = shift;

    $wordlength = $scottkit_header{wordlen};
    my $word_index = 0;
    foreach my $word ( @{$predefined_word} ) {
        my $truncated_word = uc substr $word, 0, $wordlength;
        my $synonym_index = 0;
        populate_words_at_position( $final_word, ${$predefined_word_index}[$word_index], $truncated_word,
            $unique_word );
        $word_index++;
    }
}

sub populate_words_at_position {
    my $final_word  = shift;
    my $final_index = shift;
    my $word_to_add = shift;
    my $unique_word = shift;

    if ( exists ${$unique_word}{$word_to_add} ) {
        my $synonym_index = 0;
        ${$final_word}[ $synonym_index + $final_index ] = $word_to_add;
        foreach my $synonym ( @{ ${$unique_word}{$word_to_add} } ) {
            $synonym_index++;
            ${$final_word}[ $synonym_index + $final_index ] = q{*} . $synonym;
        }
        delete ${$unique_word}{$word_to_add};
    }
}

sub parse_scottkit_data {
    my $input_text;
    while (<>) {
        $input_text .= $_;
    }
    $input_text .= "\n";    # Workaround for bug, when there is no empty last line

    my $condition_item_pattern   = qr/\s+([^"\s]+|"[^"]*")/sx;
    my $condition_none_pattern   = qr/()/sx;
    my $condition_number_pattern = qr/\s+(-?\d+)/sx;
    my $condition_room_pattern   = qr/\s+([^"\s]+|"[^"]*")/sx;

    my $command_item_item_pattern = qr/\s+([^"\s]+|"[^"]*")\s+([^"\s]+|"[^"]*")/sx;
    my $command_item_pattern      = qr/\s+([^"\s]+|"[^"]*")()/sx;
    my $command_item_room_pattern = qr/\s+([^"\s]+|"[^"]*")\s+([^"\s]+|"[^"]*")/sx;
    my $command_none_pattern      = qr/()()/sx;
    my $command_number_pattern    = qr/\s+(-?\d+)()/sx;
    my $command_room_pattern      = qr/\s+([^"\s]+|"[^"]*")()/sx;
    my $command_message_pattern   = qr/\s+([^"\s]+|"[^"]*")()/sx;

    my @condition_pattern = (
        qr/^\s+"?(carried)"?${condition_item_pattern}(.*)/sx,
        qr/^\s+"?(here)"?${condition_item_pattern}(.*)/sx,
        qr/^\s+"?(present)"?${condition_item_pattern}(.*)/sx,
        qr/^\s+"?(at)"?${condition_room_pattern}(.*)/sx,
        qr/^\s+"?(!here)"?${condition_item_pattern}(.*)/sx,
        qr/^\s+"?(!carried)"?${condition_item_pattern}(.*)/sx,
        qr/^\s+"?(!at)"?${condition_room_pattern}(.*)/sx,
        qr/^\s+"?(flag)"?${condition_number_pattern}(.*)/sx,
        qr/^\s+"?(!flag)"?${condition_number_pattern}(.*)/sx,
        qr/^\s+"?(loaded)"?${condition_none_pattern}(.*)/sx,
        qr/^\s+"?(!loaded)"?${condition_none_pattern}(.*)/sx,
        qr/^\s+"?(!present)"?${condition_item_pattern}(.*)/sx,
        qr/^\s+"?(exists)"?${condition_item_pattern}(.*)/sx,
        qr/^\s+"?(!exists)"?${condition_item_pattern}(.*)/sx,
        qr/^\s+"?(counter_le)"?${condition_number_pattern}(.*)/sx,
        qr/^\s+"?(counter_gt)"?${condition_number_pattern}(.*)/sx,
        qr/^\s+"?(!moved)"?${condition_item_pattern}(.*)/sx,
        qr/^\s+"?(moved)"?${condition_item_pattern}(.*)/sx,
        qr/^\s+"?(counter_eq)"?${condition_number_pattern}(.*)/sx,
    );

    my @command_pattern = (
        qr/^\s+"?(print)"?(?=\s)${command_message_pattern}(.*)/sx,
        qr/^\s+"?(comment)"?${command_message_pattern}(.*)/sx,
        qr/^\s+"?(get)"?${command_item_pattern}(.*)/sx,
        qr/^\s+"?(drop)"?${command_item_pattern}(.*)/sx,
        qr/^\s+"?(goto)"?${command_room_pattern}(.*)/sx,
        qr/^\s+"?(destroy)"?(?=\s)${command_item_pattern}(.*)/sx,
        qr/^\s+"?(set_dark)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(clear_dark)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(set_flag)"?(?=\s)${command_number_pattern}(.*)/sx,
        qr/^\s+"?(destroy2)"?${command_item_pattern}(.*)/sx,
        qr/^\s+"?(clear_flag)"?(?=\s)${command_number_pattern}(.*)/sx,
        qr/^\s+"?(die)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(put)"?(?=\s)${command_item_room_pattern}(.*)/sx,
        qr/^\s+"?(game_over)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(look)"?(?=\s)${command_none_pattern}(.*)/sx,
        qr/^\s+"?(score)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(inventory)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(set_flag0)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(clear_flag0)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(refill_lamp)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(clear)"?(?=\s)${command_none_pattern}(.*)/sx,
        qr/^\s+"?(save_game)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(swap)"?(?=\s)${command_item_item_pattern}(.*)/sx,
        qr/^\s+"?(continue)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(superget)"?${command_item_pattern}(.*)/sx,
        qr/^\s+"?(put_with)"?${command_item_item_pattern}(.*)/sx,
        qr/^\s+"?(look2)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(dec_counter)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(print_counter)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(set_counter)"?${command_number_pattern}(.*)/sx,
        qr/^\s+"?(swap_room)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(select_counter)"?${command_number_pattern}(.*)/sx,
        qr/^\s+"?(add_to_counter)"?${command_number_pattern}(.*)/sx,
        qr/^\s+"?(subtract_from_counter)"?${command_number_pattern}(.*)/sx,
        qr/^\s+"?(print_noun)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(println_noun)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(println)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(swap_specific_room)"?${command_number_pattern}(.*)/sx,
        qr/^\s+"?(pause)"?${command_none_pattern}(.*)/sx,
        qr/^\s+"?(draw)"?${command_number_pattern}(.*)/sx,
    );

    # Auto action
    my $occur_pattern = qr/^\s*occur(?:\s+(\d+)%)?(.*)/sx;

    # Word action
    my $action_pattern = qr/^\s*action\s+([\w-]+)(?:\s*(?:(?=when)|:)|\s+([\w-]+):?)(.*)/sx;

    my $condition_prefix_pattern   = qr/^\s*when(.*)/sx;
    my $condition_continue_pattern = qr/^\s+and(.*)/sx;

    # Room
    my $room_pattern = qr/^\s*room\s+([^"\s]+|"[^"]*")\s+([^"\s]+|"[^"]*")(.*)/sx;
    my $exit_pattern = qr/^\s*exit\s+([^"\s]+|"[^"]*")\s+([^"\s]+|"[^"]*")(.*)/sx;

    # Item
    my $item_pattern      = qr/^\s*item\s+([^"\s]+|"[^"]*")\s+([^"\s]+|"[^"]*")(.*)/sx;
    my $item_noun_pattern = qr/^\s*called\s+([^"\s]+|"[^"]*")(.*)/sx;
    my $item_room_pattern = qr/^\s*(at\s+(?:[^"\s]+|"[^"]*")|nowhere|carried)(?=\s)(.*)/sx;

    # Verb- and noun groups
    my $verbgroup_pattern = qr/^\s*verbgroup\s+((?:[\w-]+|"[^"]*")(?:[\t ]+(?:[\w-]+|"[^"]*"))+)(.*)/sx;
    my $noungroup_pattern = qr/^\s*noungroup\s+((?:[\w-]+|"[^"]*")(?:[\t ]+(?:[\w-]+|"[^"]*"))+)(.*)/sx;

    # Comments
    my $comment_pattern = qr/^\s*\#[^\n]*(.*)/sx;

    # Header entries
    my $number_header_pattern = qr/^\s*(ident|lighttime|maxload|unknown1|unknown2|version|wordlen)\s*(-?\d+)(.*)/sx;
    my $string_header_pattern = qr/^\s*(lightsource|start|treasury)\s+((?:\w+|"[^"]*"))(.*)/sx;

    my $next = $input_text;
    my $action_verb;
    my $action_noun;
    my $occur_chance;

    my $room_id;
    my $room_description;
    my $exit_direction;
    my $exit_destination;

    my $verbgroup_text;
    my $noungroup_text;

    my $item_id;
    my $item_description;
    my $item_noun;
    my $item_room;

    my $header_name;
    my $header_value;

    my $parser_state = 'root';    # Begin the parsing in state 'root'

    # Initialize data counters to -1
    my $action_counter    = $INITIAL_DATA_COUNTER_VALUE;
    my $room_counter      = $INITIAL_DATA_COUNTER_VALUE;
    my $verbgroup_counter = $INITIAL_DATA_COUNTER_VALUE;
    my $noungroup_counter = $INITIAL_DATA_COUNTER_VALUE;
    my $item_counter      = $INITIAL_DATA_COUNTER_VALUE;

    # Create room for inventory
    $room_counter++;
    $scottkit_room[$room_counter]{id}          = 'carried';
    $scottkit_room[$room_counter]{description} = q{};

    # Create storage room
    $room_counter++;
    $scottkit_room[$room_counter]{id}          = 'nowhere';
    $scottkit_room[$room_counter]{description} = q{};

    while ( length $input_text > 0 ) {

        # Comment
        if ( $next =~ /$comment_pattern/sx ) {
            ($next) = $next =~ /$comment_pattern/sx;
            next;
        }

        if ( $parser_state eq 'root' ) {

            # Action
            if ( $next =~ /$action_pattern/sx ) {
                my $line_number = lines_in_string( $input_text, $next );
                $action_counter++;
                ( $action_verb, $action_noun, $next ) = $next =~ /$action_pattern/sx;
                if ( !defined $action_noun ) {
                    $action_noun = 'ANY';

                }
                $scottkit_action[$action_counter]{type}                 = 'word';
                $scottkit_action[$action_counter]{line}                 = $line_number;
                $scottkit_action[$action_counter]{verb}                 = "\"$action_verb\"";
                $scottkit_action[$action_counter]{noun}                 = "\"$action_noun\"";
                $scottkit_action[$action_counter]{condition}            = [];
                $scottkit_action[$action_counter]{command}              = [];
                $scottkit_action_comment[ scalar @scottkit_action - 1 ] = q{};
                $parser_state                                           = 'action_header';
                next;
            }

            # Occurrence
            if ( $next =~ /$occur_pattern/sx ) {
                my $line_number = lines_in_string( $input_text, $next );
                $action_counter++;
                ( $occur_chance, $next ) = $next =~ /$occur_pattern/sx;
                if ( !defined $occur_chance ) {
                    $occur_chance = 100;
                }
                $scottkit_action[$action_counter]{type}                 = 'number';
                $scottkit_action[$action_counter]{line}                 = $line_number;
                $scottkit_action[$action_counter]{verb}                 = 0;
                $scottkit_action[$action_counter]{noun}                 = $occur_chance;
                $scottkit_action[$action_counter]{condition}            = [];
                $scottkit_action[$action_counter]{command}              = [];
                $scottkit_action_comment[ scalar @scottkit_action - 1 ] = q{};
                $parser_state                                           = 'action_header';
                next;
            }

            # Room
            if ( $next =~ /$room_pattern/sx ) {
                my $line_number = lines_in_string( $input_text, $next );
                $room_counter++;
                ( $room_id, $room_description, $next ) = $next =~ /$room_pattern/sx;

                # Terminate if the room id already exists
                foreach my $existing_room (@scottkit_room) {
                    my $existing_id = ${$existing_room}{id};
                    if ( $existing_id eq $room_id ) {
                        print STDERR "ERROR: Room ID \"$existing_id\" on line $line_number already exists.\n";
                        exit 1;
                    }
                }

                $scottkit_room[$room_counter]{line}        = $line_number;
                $scottkit_room[$room_counter]{id}          = $room_id;
                $scottkit_room[$room_counter]{description} = $room_description;
                $parser_state                              = 'room';
                next;
            }

            # Verbgroup
            if ( $next =~ /$verbgroup_pattern/sx ) {
                my $line_number = lines_in_string( $input_text, $next );
                $verbgroup_counter++;
                ( $verbgroup_text, $next ) = $next =~ /$verbgroup_pattern/sx;
                my @verb = split /\s+/, $verbgroup_text;
                my $primary_verb = shift @verb;
                $scottkit_verbgroup{$primary_verb}{line}    = $line_number;
                $scottkit_verbgroup{$primary_verb}{synonym} = \@verb;
                next;
            }

            # Noungroup
            if ( $next =~ /$noungroup_pattern/sx ) {
                my $line_number = lines_in_string( $input_text, $next );
                $noungroup_counter++;
                ( $noungroup_text, $next ) = $next =~ /$noungroup_pattern/sx;
                my @noun = split /\s+/, $noungroup_text;
                my $primary_noun = shift @noun;
                $scottkit_noungroup{$primary_noun}{line}    = $line_number;
                $scottkit_noungroup{$primary_noun}{synonym} = \@noun;
                next;
            }

            # Item
            if ( $next =~ /$item_pattern/sx ) {
                my $line_number = lines_in_string( $input_text, $next );
                $item_counter++;
                ( $item_id, $item_description, $next ) = $next =~ /$item_pattern/sx;
                $scottkit_item[$item_counter]{line}        = $line_number;
                $scottkit_item[$item_counter]{id}          = $item_id;
                $scottkit_item[$item_counter]{description} = $item_description;
                $scottkit_item[$item_counter]{room}        = $scottkit_room[$room_counter]{id};
                $parser_state                              = 'item';
                next;
            }

            # Header fields with numbers
            if ( $next =~ /$number_header_pattern/sx ) {
                ( $header_name, $header_value, $next ) = $next =~ /$number_header_pattern/sx;
                $scottkit_header{$header_name} = $header_value;
                next;
            }

            # Header fields with strings
            if ( $next =~ /$string_header_pattern/sx ) {
                ( $header_name, $header_value, $next ) = $next =~ /$string_header_pattern/sx;
                $scottkit_header{$header_name} = $header_value;
                next;
            }
        }

        # Action / occurrence
        if ( $parser_state eq 'action_header' ) {
            if ( $next =~ /$condition_prefix_pattern/sx ) {
                ($next) = $next =~ /$condition_prefix_pattern/sx;
                $parser_state = 'condition';
            }
            else {
                $parser_state = 'command';
            }
            next;
        }

        if ( $parser_state eq 'condition' ) {
            my $found_pattern;
            foreach my $pattern (@condition_pattern) {
                if ( $next =~ /$pattern/sx ) {
                    $found_pattern = $pattern;
                    last;
                }
            }
            if ( defined $found_pattern ) {
                my ( $condition_code, $argument );
                ( $condition_code, $argument, $next ) = $next =~ /$found_pattern/sx;
                my %condition_payload = ( 'code' => $condition_code, 'argument' => $argument );
                push @{ $scottkit_action[$action_counter]{condition} }, \%condition_payload;

                if ( $next =~ /$condition_continue_pattern/sx ) {
                    ($next) = $next =~ /$condition_continue_pattern/sx;
                }
                else {
                    $parser_state = 'command';
                }
                next;
            }
        }

        if ( $parser_state eq 'command' ) {
            my $found_pattern;
            foreach my $pattern (@command_pattern) {
                if ( $next =~ /^$pattern/sx ) {
                    $found_pattern = $pattern;
                    last;
                }
            }

            if ( defined $found_pattern ) {
                my ( $command_code, $argument_1, $argument_2 );
                ( $command_code, $argument_1, $argument_2, $next ) = $next =~ /$found_pattern/sx;

                # Remove quotes from print argument if it has them
                if ( $command_code eq 'print' ) {
                    $argument_1 =~ s/^"([\S\s]*)"$/$1/sx;
                }

                if ( $command_code eq 'comment' ) {
                    $scottkit_action_comment[ scalar @scottkit_action - 1 ] = $argument_1;
                }
                else {
                    my %command_payload = (
                        'code'       => $command_code,
                        'argument_1' => $argument_1,
                        'argument_2' => $argument_2,
                    );
                    push @{ $scottkit_action[$action_counter]{command} }, \%command_payload;
                }
                next;
            }

            # Exit parser state 'command' if no more found
            $parser_state = 'root';
            next;
        }

        # Room
        if ( $parser_state eq 'room' ) {
            if ( $next =~ /^$exit_pattern/sx ) {
                ( $exit_direction, $exit_destination, $next ) = $next =~ /$exit_pattern/sx;
                $scottkit_room[$room_counter]{exit}{$exit_direction} = $exit_destination;
                next;
            }

            # Exit parser state 'room' if no more exits found
            $parser_state = 'root';
            next;
        }

        # Item
        if ( $parser_state eq 'item' ) {
            if ( $next =~ /^$item_noun_pattern/sx ) {
                ( $item_noun, $next ) = $next =~ /$item_noun_pattern/sx;
                $scottkit_item[$item_counter]{noun} = $item_noun;
                next;
            }

            if ( $next =~ /^$item_room_pattern/sx ) {
                ( $item_room, $next ) = $next =~ /$item_room_pattern/sx;
                $item_room =~ s/^at\s+//sx;
                $scottkit_item[$item_counter]{room} = $item_room;
                next;
            }

            # Exit parser state 'item' if no more item details found
            $parser_state = 'root';
            next;
        }

        # Catch unknown lines
        if ( $next !~ /^\s*$/sx ) {
            $next =~ s/^\s+//sx;
            my $line_number_with_problem = lines_in_string( $input_text, $next );
            my ($single_line) = $next =~ /^([^\n]*)/sx;
            print STDERR "ERROR: Failed to parse text on line $line_number_with_problem: \"$single_line\"\n";
            exit 1;
        }
        last;
    }
}

# This can be used to figure out which line in the SCK file we are on, by
# counting the number of newlines in the remaining buffer and comparing that
# to the number of newlines in the original data file. Example:
#     print "DEBUG: line " . lines_in_string ($input_text, $next) . "\n";
sub lines_in_string {
    my $string_to_examine_1 = shift;
    my $string_to_examine_2 = shift;
    $string_to_examine_2 =~ s/^\s*//;
    my $lines_1 = scalar split /\n/, $string_to_examine_1;
    my $lines_2 = scalar split /\n/, $string_to_examine_2;
    return $lines_1 - $lines_2 + 1;
}
