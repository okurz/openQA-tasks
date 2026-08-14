#!/usr/bin/env perl
# Seed the local test database with fixtures plus a scenario that has jobs
# declaring _HISTORY_ISOLATION_KEYS, so the "Next & Previous" strict toggle
# shows up in the web UI.
#
# OpenQA::Schema locates its dbicdh/ schema files by walking up from
# $FindBin::Bin, so this script must live inside the openQA checkout when run.
# Copy it into the repo's t/ directory first (see the shell recipe below).
#
# Usage (from the openQA checkout root, after `t/test_postgresql`):
#   cp tasks/setup_isolation_demo.pl t/
#   TEST_PG='DBI:Pg:dbname=openqa_test;host=/dev/shm/tpg' OPENQA_BASEDIR=t/data \
#     perl -Ilib -It/lib t/setup_isolation_demo.pl
#   rm t/setup_isolation_demo.pl
#
# Then start the web UI against the same database and open the created job:
#   TEST_PG='DBI:Pg:dbname=openqa_test;host=/dev/shm/tpg' OPENQA_DATABASE=test \
#     OPENQA_BASEDIR=t/data morbo -m development -w assets -w lib -w templates \
#     -l http://localhost:9526 script/openqa daemon
# Open http://localhost:9526/tests/<last-created-id> -> "Next & previous
# results" tab; the "Strict scenario (isolate history by PR_ID)" switch appears.
use Mojo::Base -strict, -signatures;
use FindBin;
use lib "$FindBin::Bin/lib";
use OpenQA::Test::Database;
use OpenQA::Jobs::Constants;

my $schema = OpenQA::Test::Database->new->create(
    skip_schema => 1,    # use the default (public) schema the daemon reads
    fixtures_glob => '01-jobs.pl 03-users.pl 04-products.pl 05-job_modules.pl 07-needles.pl',
);
my $jobs = $schema->resultset('Jobs');

# a scenario with independent PRs, all sharing scenario keys, isolated by PR_ID
my %base = (
    group_id => 1001, priority => 40, state => 'done',
    DISTRI => 'opensuse', VERSION => 'Tumbleweed', FLAVOR => 'DVD',
    ARCH => 'x86_64', TEST => 'isolation_demo', MACHINE => '64bit',
);
my @spec = (    # [BUILD, result, PR_ID]
    ['PR-100.1', 'passed', 100],
    ['PR-100.2', 'failed', 100],
    ['PR-200.1', 'passed', 200],
    ['PR-100.3', 'failed', 100],
    ['PR-200.2', 'softfailed', 200],
    ['PR-100.4', 'failed', 100],
);
my @created;
for my $s (@spec) {
    my ($build, $result, $pr) = @$s;
    my $job = $jobs->create({
        %base, BUILD => $build, result => $result,
        settings => [
            {key => 'PR_ID', value => $pr},
            {key => '_HISTORY_ISOLATION_KEYS', value => 'PR_ID'},
            {key => 'BUILD', value => $build},
        ],
    });
    push @created, $job->id;
}
printf "Created isolated jobs: %s\n", join ', ', @created;
printf "Open any of them, e.g. /tests/%d , and use the 'Next & previous results' tab.\n", $created[-1];
printf "The strict toggle 'isolate history by PR_ID' should appear.\n";
