#!/bin/sh

test_description="Test whether cache-tree is properly updated

Tests whether various commands properly update and/or rewrite the
cache-tree extension.
"
 . ./test-lib.sh

cmp_cache_tree () {
	test-dump-cache-tree | sed -e '/#(ref)/d' >actual &&
	sed "s/$_x40/SHA/" <actual >filtered &&
	test_cmp "$1" filtered
}

# We don't bother with actually checking the SHA1:
# test-dump-cache-tree already verifies that all existing data is
# correct.
generate_expected_cache_tree () {
	dir="$1${1:+/}" &&
	parent="$2" &&
	# ls-files might have foo/bar, foo/bar/baz, and foo/bar/quux
	# We want to count only foo because it's the only direct child
	subtrees=$(git ls-files|grep /|cut -d / -f 1|uniq) &&
	subtree_count=$(echo "$subtrees"|awk '$1 {++c} END {print c}') &&
	entries=$(git ls-files|wc -l) &&
	printf "SHA $dir (%d entries, %d subtrees)\n" $entries $subtree_count &&
	for subtree in $subtrees
	do
	    cd "$subtree"
	    generate_expected_cache_tree "$dir$subtree" $dir || return 1
	    cd ..
	done &&
	dir=$parent
}

test_cache_tree () {
	generate_expected_cache_tree >expect &&
	cmp_cache_tree expect
}

test_invalid_cache_tree () {
	printf "invalid                                  %s ()\n" "" "$@" >expect &&
	test-dump-cache-tree | \
	sed -n -e "s/$_x40/SHA/" -e "s/[0-9]* subtrees//g" -e '/#(ref)/d' -e '/^invalid /p' >actual &&
	test_cmp expect actual
}

test_no_cache_tree () {
	: >expect &&
	cmp_cache_tree expect
}

test_expect_success 'initial commit has cache-tree' '
	test_commit foo &&
	test_cache_tree
'

test_expect_success 'read-tree HEAD establishes cache-tree' '
	git read-tree HEAD &&
	test_cache_tree
'

test_expect_success 'git-add invalidates cache-tree' '
	test_when_finished "git reset --hard; git read-tree HEAD" &&
	echo "I changed this file" >foo &&
	git add foo &&
	test_invalid_cache_tree
'

test_expect_success 'git-add in subdir invalidates cache-tree' '
	test_when_finished "git reset --hard; git read-tree HEAD" &&
	mkdir dirx &&
	echo "I changed this file" >dirx/foo &&
	git add dirx/foo &&
	test_invalid_cache_tree
'

cat >before <<\EOF
SHA  (3 entries, 2 subtrees)
SHA dir1/ (1 entries, 0 subtrees)
SHA dir2/ (1 entries, 0 subtrees)
EOF

cat >expect <<\EOF
invalid                                   (2 subtrees)
invalid                                  dir1/ (0 subtrees)
SHA dir2/ (1 entries, 0 subtrees)
EOF

test_expect_success 'git-add in subdir does not invalidate sibling cache-tree' '
	git tag no-children &&
	test_when_finished "git reset --hard no-children; git read-tree HEAD" &&
	mkdir dir1 dir2 &&
	test_commit dir1/a &&
	test_commit dir2/b &&
	echo "I changed this file" >dir1/a &&
	cmp_cache_tree before &&
	echo "I changed this file" >dir1/a &&
	git add dir1/a &&
	cmp_cache_tree expect
'

test_expect_success 'update-index invalidates cache-tree' '
	test_when_finished "git reset --hard; git read-tree HEAD" &&
	echo "I changed this file" >foo &&
	git update-index --add foo &&
	test_invalid_cache_tree
'

test_expect_success 'write-tree establishes cache-tree' '
	test-scrap-cache-tree &&
	git write-tree &&
	test_cache_tree
'

test_expect_success 'test-scrap-cache-tree works' '
	git read-tree HEAD &&
	test-scrap-cache-tree &&
	test_no_cache_tree
'

test_expect_success 'second commit has cache-tree' '
	test_commit bar &&
	test_cache_tree
'

test_expect_success 'commit in child dir has cache-tree' '
	mkdir dir &&
	>dir/child.t &&
	git add dir/child.t &&
	git commit -m dir/child.t &&
	test_cache_tree
'

test_expect_success 'reset --hard gives cache-tree' '
	test-scrap-cache-tree &&
	git reset --hard &&
	test_cache_tree
'

test_expect_success 'reset --hard without index gives cache-tree' '
	rm -f .git/index &&
	git reset --hard &&
	test_cache_tree
'

test_expect_success 'checkout gives cache-tree' '
	git tag current &&
	git checkout HEAD^ &&
	test_cache_tree
'

test_expect_success 'checkout -b gives cache-tree' '
	git checkout current &&
	git checkout -b prev HEAD^ &&
	test_cache_tree
'

test_expect_success 'checkout -B gives cache-tree' '
	git checkout current &&
	git checkout -B prev HEAD^ &&
	test_cache_tree
'

test_expect_success 'partial commit gives cache-tree' '
	git checkout -b partial no-children &&
	test_commit one &&
	test_commit two &&
	echo "some change" >one.t &&
	git add one.t &&
	echo "some other change" >two.t &&
	git commit two.t -m partial &&
	test_cache_tree
'

test_done
