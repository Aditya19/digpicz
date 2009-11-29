#!/usr/bin/perl
#
# Copyright (C) 2007 Peteris Krumins (peter@catonmat.net)
# http://www.catonmat.net  -  good coders code, great reuse
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use warnings;
use strict;

#
# this script takes input in format:
#  title: story title
#  type: story type
#  desc: story description
#  url: story url
#  digg_url: url to original story on digg
#  category: digg category of the story
#  short_category: short cateogry name
#  user: username
#  user_pic: url to user pic
#  date: date story appeared on digg YYYY-MM-DD HH::MM::SS
# and inserts all this info in an sqlite database
#
# it is made to work with digg_extractor.pl script but can be fed
# any input which is in that format
#

use DBI;
use POSIX;

#
# This program was written as a part of "digpicz: digg's missing picture section"
# website generator.
# This website can be viewed here: http://digpicz.com
#
# See http://www.catonmat.net/designing-digg-picture-website for more info.
#

binmode(STDIN, ':utf8');

use constant DATABASE_PATH => '/mnt/evms/services/apache/wwwroot/digpicz/db/media.db';

my $dbh = DBI->connect("dbi:SQLite:" . DATABASE_PATH, '', '', { RaiseError => 1 });
die $DBI::errstr unless $dbh;

create_db_if_not_exists();

# no normalization of database whatsoever, we just want the site to be running.
# bad, bad, bad!
my $insert_query =<<EOL; 
INSERT INTO digg (title, desc, type, url, digg_url, digg_category, digg_short_category, user, user_avatar, date_added)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
EOL
my $sth = $dbh->prepare($insert_query);

# turn on paragraph slurp mode
$/ = '';
while (<>) {
    next if /^#/;       # ignore comments
    parse_and_insert_db($_);
}

#
# if we do not  set $sth to undef, we get the following warning:
#
# DBI::db=HASH(0x1d287e8)->disconnect invalidates 1 active statement handle
# (either destroy statement handles or call finish on them before disconnecting)
# at db_inserter.pl line 65, <> line 4.
#
# closing dbh with active statement handles at db_inserter.pl line 65, <> line 4.
#
$sth = undef;

$dbh->disconnect;

#
# parse_and_insert_db
#
# Parses and inserts a paragraph into database.
#
sub parse_and_insert_db {
    my $par = shift;
    my @parts = split '\n', $par;
    my %story;

    foreach (@parts) {
        my ($val, $key) = split ': ', $_, 2;
        $story{$val} = $key;
    }
    
    $sth->execute($story{title}, $story{desc}, $story{type}, $story{url}, $story{digg_url},
                  $story{category}, $story{short_category}, $story{user}, $story{user_pic},
                  $story{date});
}

#
# create_db_if_not_exists
#
# Creates reddit table if it does not exit
#
sub create_db_if_not_exists {
    # Older versions of sqlite 3 do not support IF NOT EXISTS clause,
    # we have to workaround
    #
    my $table_exists = 0;
    my $tables_q = "SELECT name FROM sqlite_master WHERE type='table' AND name='digg'";
    my $res = $dbh->selectall_arrayref($tables_q);

    if (defined $res and @$res) {
        $table_exists = 1;
    }

    unless ($table_exists) {

        my $create_db =<<EOL;
CREATE TABLE digg (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    title           STRING  NOT NULL    UNIQUE,
    desc            STRING  NOT NULL    UNIQUE,
    url             STRING  NOT NULL    UNIQUE,
    digg_url        STRING  NOT NULL    UNIQUE,
    digg_category   STRING  NOT NULL,
    digg_short_category   STRING  NOT NULL,
    user            STRING  NOT NULL,
    user_avatar     STRING  NOT NULL,
    type            STRING  NOT NULL,
    date_added      DATE    NOT NULL
)
EOL

        $dbh->do($create_db);
    }
}

