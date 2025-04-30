```clarity
;; TrendGrid - Fashion Trends Tracking Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-season (err u101))
(define-constant err-invalid-votes (err u102))
(define-constant err-already-voted (err u103))
(define-constant err-invalid-flag-reason (err u104))
(define-constant err-already-flagged (err u105))
(define-constant err-reward-distribution-failed (err u106))

;; Data Variables
(define-data-var next-trend-id uint u0)
(define-data-var next-reward-id uint u0)

;; Data Maps
(define-map trends 
    uint 
    {
        submitter: principal,
        region: (string-ascii 50),
        season: (string-ascii 10),
        style: (string-ascii 100),
        description: (string-ascii 500),
        votes: uint,
        flags: uint,
        timestamp: uint
    }
)

(define-map user-votes 
    {trend-id: uint, voter: principal} 
    bool
)

(define-map user-flags
    {trend-id: uint, flagger: principal}
    {reason: (string-ascii 100)}
)

(define-map trend-analytics
    {region: (string-ascii 50), season: (string-ascii 10)}
    {count: uint, total-votes: uint}
)

(define-map user-rewards
    principal
    {total-earned: uint, last-claim: uint}
)

(define-map reward-distribution
    uint
    {recipient: principal, amount: uint, trend-id: uint, timestamp: uint}
)

;; Private Functions
(define-private (is-valid-season (season (string-ascii 10)))
    (or 
        (is-eq season "SPRING")
        (is-eq season "SUMMER")
        (is-eq season "FALL")
        (is-eq season "WINTER")
    )
)

(define-private (is-valid-flag-reason (reason (string-ascii 100)))
    (or
        (is-eq reason "INAPPROPRIATE")
        (is-eq reason "DUPLICATE")
        (is-eq reason "INACCURATE")
        (is-eq reason "SPAM")
    )
)

(define-private (update-analytics (region (string-ascii 50)) (season (string-ascii 10)) (vote-change uint))
    (let
        (
            (current-analytics (default-to {count: u0, total-votes: u0} 
                              (map-get? trend-analytics {region: region, season: season})))
        )
        (map-set trend-analytics 
                {region: region, season: season} 
                {
                    count: (+ (get count current-analytics) u1),
                    total-votes: (+ (get total-votes current-analytics) vote-change)
                })
    )
)

(define-private (award-submission-reward (submitter principal) (trend-id uint))
    (let
        (
            (reward-id (var-get next-reward-id))
            (reward-amount u10)
            (user-reward (default-to {total-earned: u0, last-claim: u0} 
                        (map-get? user-rewards submitter)))
        )
        (map-set reward-distribution reward-id 
                {
                    recipient: submitter,
                    amount: reward-amount,
                    trend-id: trend-id,
                    timestamp: block-height
                })
        (map-set user-rewards submitter 
                {
                    total-earned: (+ (get total-earned user-reward) reward-amount),
                    last-claim: block-height
                })
        (var-set next-reward-id (+ reward-id u1))
        (ok reward-amount)
    )
)

;; Public Functions
(define-public (submit-trend (region (string-ascii 50)) (season (string-ascii 10)) (style (string-ascii 100)) (description (string-ascii 500)))
    (let 
        (
            (trend-id (var-get next-trend-id))
        )
        (if (is-valid-season season)
            (begin
                (map-set trends trend-id {
                    submitter: tx-sender,
                    region: region,
                    season: season,
                    style: style,
                    description: description,
                    votes: u0,
                    flags: u0,
                    timestamp: block-height
                })
                (var-set next-trend-id (+ trend-id u1))
                (update-analytics region season u0)
                (award-submission-reward tx-sender trend-id)
                (ok trend-id)
            )
            err-invalid-season
        )
    )
)

(define-public (vote-on-trend (trend-id uint))
    (let
        (
            (has-voted (default-to false (map-get? user-votes {trend-id: trend-id, voter: tx-sender})))
            (trend (unwrap! (map-get? trends trend-id) (err u404)))
        )
        (if (not has-voted)
            (begin
                (map-set trends trend-id (merge trend {votes: (+ (get votes trend) u1)}))
                (map-set user-votes {trend-id: trend-id, voter: tx-sender} true)
                (update-analytics (get region trend) (get season trend) u1)
                (ok true)
            )
            err-already-voted
        )
    )
)

(define-public (flag-trend (trend-id uint) (reason (string-ascii 100)))
    (let
        (
            (has-flagged (is-some (map-get? user-flags {trend-id: trend-id, flagger: tx-sender})))
            (trend (unwrap! (map-get? trends trend-id) (err u404)))
        )
        (if (not has-flagged)
            (if (is-valid-flag-reason reason)
                (begin
                    (map-set trends trend-id (merge trend {flags: (+ (get flags trend) u1)}))
                    (map-set user-flags {trend-id: trend-id, flagger: tx-sender} {reason: reason})
                    (ok true)
                )
                err-invalid-flag-reason
            )
            err-already-flagged
        )
    )
)

(define-public (community-moderate (trend-id uint) (should-remove bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-trend (trend-id uint))
    (ok (map-get? trends trend-id))
)

(define-read-only (get-trends-count)
    (ok (var-get next-trend-id))
)

(define-read-only (get-trends-by-region (region (string-ascii 50)))
    (let
        (
            (trend-count (var-get next-trend-id))
        )
        (ok (filter get-trend-by-region (list-trends trend-count)))
    )
)

(define-read-only (get-trends-by-season (season (string-ascii 10)))
    (let
        (
            (trend-count (var-get next-trend-id))
        )
        (ok (filter get-trend-by-season (list-trends trend-count)))
    )
)

(define-read-only (get-top-trends (limit uint))
    (let
        (
            (trend-count (var-get next-trend-id))
            (all-trends (list-trends trend-count))
        )
        (ok (filter-not-none (take limit (sort-trends-by-votes all-trends))))
    )
)

(define-read-only (get-recent-trends (limit uint))
    (let
        (
            (trend-count (var-get next-trend-id))
            (all-trends (list-trends trend-count))
        )
        (ok (filter-not-none (take limit (sort-trends-by-timestamp all-trends))))
    )
)

(define-read-only (get-region-season-analytics (region (string-ascii 50)) (season (string-ascii 10)))
    (ok (map-get? trend-analytics {region: region, season: season}))
)

(define-read-only (get-user-rewards (user principal))
    (ok (map-get? user-rewards user))
)

(define-private (get-trend-by-region (trend {id: uint, data: (optional {submitter: principal, region: (string-ascii 50), season: (string-ascii 10), style: (string-ascii 100), description: (string-ascii 500), votes: uint, flags: uint, timestamp: uint})}))
    (match (get data trend)
        data (is-eq (get region data) region)
        false
    )
)

(define-private (get-trend-by-season (trend {id: uint, data: (optional {submitter: principal, region: (string-ascii 50), season: (string-ascii 10), style: (string-ascii 100), description: (string-ascii 500), votes: uint, flags: uint, timestamp: uint})}))
    (match (get data trend)
        data (is-eq (get season data) season)
        false
    )
)

(define-private (sort-trends-by-votes (trends (list {id: uint, data: (optional {submitter: principal, region: (string-ascii 50), season: (string-ascii 10), style: (string-ascii 100), description: (string-ascii 500), votes: uint, flags: uint, timestamp: uint})})))
    (list-sort compare-trend-votes trends)
)

(define-private (sort-trends-by-timestamp (trends (list {id: uint, data: (optional {submitter: principal, region: (string-ascii 50), season: (string-ascii 10), style: (string-ascii 100), description: (string-ascii 500), votes: uint, flags: uint, timestamp: uint})})))
    (list-sort compare-trend-timestamp trends)
)

(define-private (compare-trend-votes (a {id: uint, data: (optional {submitter: principal, region: (string-ascii 50), season: (string-ascii 10), style: (string-ascii 100), description: (string-ascii 500), votes: uint, flags: uint, timestamp: uint})}) 
                                    (b {id: uint, data: (optional {submitter: principal, region: (string-ascii 50), season: (string-ascii 10), style: (string-ascii 100), description: (string-ascii 500), votes: uint, flags: uint, timestamp: uint})}))
    (match (get data a) 
        a-data (match (get data b)
            b-data (> (get votes a-data) (get votes b-data))
            false)
        false)
)

(define-private (compare-trend-timestamp (a {id: uint, data: (optional {submitter: principal, region: (string-ascii 50), season: (string-ascii 10), style: (string-ascii 100), description: (string-ascii 500), votes: uint, flags: uint, timestamp: uint})}) 
                                       (b {id: uint, data: (optional {submitter: principal, region: (string-ascii 50), season: (string-ascii 10), style: (string-ascii 100), description: (string-ascii 500), votes: uint, flags: uint, timestamp: uint})}))
    (match (get data a) 
        a-data (match (get data b)
            b-data (> (get timestamp a-data) (get timestamp b-data))
            false)
        false)
)

(define-private (filter-not-none (trends (list {id: uint, data: (optional {submitter: principal, region: (string-ascii 50), season: (string-ascii 10), style: (string-ascii 100), description: (string-ascii 500), votes: uint, flags: uint, timestamp: uint})})))
    (filter has-data trends)
)

(define-private (has-data (trend {id: uint, data: (optional {submitter: principal, region: (string-ascii 50), season: (string-ascii 10), style: (string-ascii 100), description: (string-ascii 500), votes: uint, flags: uint, timestamp: uint})}))
    (is-some (get data trend))
)

(define-private (list-trends (n uint))
    (map unwrap-trend (range u0 n))
)

(define-private (unwrap-trend (id uint))
    {id: id, data: (map-get? trends id)}
)
```