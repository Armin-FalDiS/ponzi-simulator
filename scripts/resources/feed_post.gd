class_name FeedPost
extends Resource
## One post in the social feed. The feed replaces the accounting ledger as the
## main view's readout, so a post is not flavour — it is the only channel through
## which trust, heat and hype are allowed to reach the player (DESIGN.md §4.2).
##
## Three properties carry the three hidden meters:
##   * `tone`       — sentiment, i.e. trust
##   * `author`     — who is talking, i.e. heat (a journalist posting *is* the spike)
##   * `engagement` — likes and shares, i.e. hype

## What the post is about. Kinds are the key into the content pool, so adding a
## kind means adding `resources/feed/<kind>.tres` and nothing else.
enum Kind {
	CHATTER,   ## ambient noise; carries no signal at all
	JOINED,    ## somebody signed this week
	PAID,      ## a cheque cleared
	FLEX,      ## a paid investor showing off — this one recruits for you
	WAITING,   ## money is late and they are being polite about it
	BROKEN,    ## a delay, a part-payment, or a plain shortfall
	WITHDRAW,  ## somebody took their money out
	DOUBT,     ## sentiment souring without a specific trigger
	PRESS,     ## a byline in your mentions
	HYPE,      ## the marketing landed
	WHALE,     ## a large cheque, loudly
	COLLAPSE,  ## the run ending, in public
	## A tell: somebody noticing a thing that has not happened yet. The only kind
	## that is about *next* week, and the only one whose wording carries a number
	## — the probability band it was drawn from (DESIGN.md §4.3).
	TELL,
}

## Appended to, never reordered: the integers are baked into every
## `resources/feed/*.tres` on disk.
const KIND_NAMES: Array[String] = [
	"chatter", "joined", "paid", "flex", "waiting", "broken",
	"withdraw", "doubt", "press", "hype", "whale", "collapse", "tell",
]

@export var author: CastMember
@export var body: String = ""
@export var kind: Kind = Kind.CHATTER
## Likes and shares. Deliberately noisy — it is an impression of how loud the
## story is, never a readable hype value.
@export var engagement: int = 0
## Colour intent. The UI owns the actual colour; the sim only names the mood.
@export var tone: WeekReport.Tone = WeekReport.Tone.NEUTRAL
## Week the post was made, so the feed can rule off between weeks.
@export var week: int = 0


static func make(post_author: CastMember, text: String, post_kind: Kind,
		post_tone: WeekReport.Tone, likes: int, at_week: int) -> FeedPost:
	var post := FeedPost.new()
	post.author = post_author
	post.body = text
	post.kind = post_kind
	post.tone = post_tone
	post.engagement = likes
	post.week = at_week
	return post


func kind_name() -> String:
	return KIND_NAMES[int(kind)]
