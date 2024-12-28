;; TrendGrid - Fashion Trends Tracking Contract

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-season (err u101))
(define-constant err-invalid-votes (err u102))
(define-constant err-already-voted (err u103))

;; Data Variables
(define-data-var next-trend-id uint u0)

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
        timestamp: uint
    }
)

(define-map user-votes 
    {trend-id: uint, voter: principal} 
    bool
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
                    timestamp: block-height
                })
                (var-set next-trend-id (+ trend-id u1))
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
                (ok true)
            )
            err-already-voted
        )
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

(define-private (get-trend-by-region (trend {id: uint, data: (optional {submitter: principal, region: (string-ascii 50), season: (string-ascii 10), style: (string-ascii 100), description: (string-ascii 500), votes: uint, timestamp: uint})}))
    (match (get data trend)
        data (is-eq (get region data) region)
        false
    )
)

(define-private (list-trends (n uint))
    (map unwrap-trend (range u0 n))
)

(define-private (unwrap-trend (id uint))
    {id: id, data: (map-get? trends id)}
)