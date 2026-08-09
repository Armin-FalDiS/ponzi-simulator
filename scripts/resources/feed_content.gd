class_name FeedContent
extends Resource
## The whole content pool, as one index of `PostTemplateSet` files.
##
## An explicit list rather than a directory scan: it survives export remapping,
## it is visible in the Inspector, and a missing file fails loudly at import
## instead of quietly halving the vocabulary at runtime.

@export var sets: Array[PostTemplateSet] = []


## Every set that can supply a body for this kind, in declaration order.
## Result is not cached — `FeedComposer` indexes once at construction.
func sets_for(kind: FeedPost.Kind) -> Array[PostTemplateSet]:
	var matches: Array[PostTemplateSet] = []
	for set in sets:
		if set != null and set.kind == kind:
			matches.append(set)
	return matches
