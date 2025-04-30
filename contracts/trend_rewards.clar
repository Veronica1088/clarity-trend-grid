;; trend_rewards.clar
;; Purpose: Implement a token-based rewards system for trend submissions and voting
;;
;; This contract establishes a rewards system using semi-fungible tokens (SFTs) that 
;; represent "Fashion Influence Points." Users earn tokens for submitting trends that 
;; receive high vote counts and for participating in voting. The reward mechanism factors  
;; in trend quality (votes received), seasonal relevance, and regional diversity to 
;; encourage global fashion insights. These tokens can be used for highlighting trends, 
;; accessing premium analytics, or conversion to other tokens within the Stacks ecosystem.

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-TREND (err u101))
(define-constant ERR-INVALID-VOTE (err u102))
(define-constant ERR-ALREADY-VOTED (err u103))
(define-constant ERR-NOT-ENOUGH-TOKENS (err u104))
(define-constant ERR-INVALID-SEASON (err u105))
(define-constant ERR-INVALID-REGION (err u106))
(define-constant ERR-TREND-NOT-FOUND (err u107))
(define-constant ERR-INVALID-AMOUNT (err u108))
(define-constant ERR-CONTRACT-NOT-ENABLED (err u109))

;; Constants
(define-constant ADMIN-ADDRESS tx-sender)
(define-constant TOKEN-URI "https://clarity-trend-grid.com/token-metadata/")
(define-constant BASE-TREND-SUBMISSION-REWARD u10)
(define-constant BASE-VOTE-REWARD u1)
(define-constant TREND-BOOST-COST u50)
(define-constant ANALYTICS-ACCESS-COST u100)

;; Seasons - used for seasonal relevance multiplier
(define-constant SEASON-SPRING u1)
(define-constant SEASON-SUMMER u2)
(define-constant SEASON-FALL u3)
(define-constant SEASON-WINTER u4)

;; Regions - used for regional diversity tracking
(define-constant REGION-NORTH-AMERICA u1)
(define-constant REGION-EUROPE u2)
(define-constant REGION-ASIA u3)
(define-constant REGION-SOUTH-AMERICA u4)
(define-constant REGION-AFRICA u5)
(define-constant REGION-OCEANIA u6)

;; Token ID for Fashion Influence Points
(define-constant FASHION-INFLUENCE-POINTS-ID u1)

;; Data Maps

;; Map to track user balances of the SFT
(define-map token-balances {owner: principal, token-id: uint} uint)

;; Map to track trends by ID
(define-map trends 
  uint 
  {
    submitted-by: principal,
    votes: uint,
    season: uint,
    region: uint,
    title: (string-ascii 50),
    rewarded: bool
  }
)

;; Track who has voted on which trends
(define-map trend-votes {trend-id: uint, voter: principal} bool)

;; Used to generate unique trend IDs
(define-data-var last-trend-id uint u0)

;; Track the current season for seasonal relevance multiplier
(define-data-var current-season uint SEASON-SPRING)

;; Track if contract features are enabled/disabled
(define-data-var contract-enabled bool true)

;; Store total supply of tokens
(define-map token-supplies uint uint)

;; Private Functions

;; Initialize a token supply if not already set
(define-private (initialize-supply (token-id uint))
  (match (map-get? token-supplies token-id)
    supply true
    (map-set token-supplies token-id u0)
  )
)

;; Get token balance for a user
(define-private (get-balance (owner principal) (token-id uint))
  (default-to u0 
    (map-get? token-balances {owner: owner, token-id: token-id})
  )
)

;; Mint tokens to a user
(define-private (mint-tokens (recipient principal) (token-id uint) (amount uint))
  (begin
    ;; Ensure token supply is initialized
    (initialize-supply token-id)
    
    ;; Calculate new balance and supply
    (let (
      (current-balance (get-balance recipient token-id))
      (new-balance (+ current-balance amount))
      (current-supply (default-to u0 (map-get? token-supplies token-id)))
      (new-supply (+ current-supply amount))
    )
      ;; Update balance and supply
      (map-set token-balances {owner: recipient, token-id: token-id} new-balance)
      (map-set token-supplies token-id new-supply)
      (ok true)
    )
  )
)

;; Burn tokens from a user
(define-private (burn-tokens (owner principal) (token-id uint) (amount uint))
  (let (
    (current-balance (get-balance owner token-id))
  )
    ;; Check if user has enough balance
    (if (>= current-balance amount)
      (let (
        (new-balance (- current-balance amount))
        (current-supply (default-to u0 (map-get? token-supplies token-id)))
        (new-supply (- current-supply amount))
      )
        ;; Update balance and supply
        (map-set token-balances {owner: owner, token-id: token-id} new-balance)
        (map-set token-supplies token-id new-supply)
        (ok true)
      )
      ERR-NOT-ENOUGH-TOKENS
    )
  )
)

;; Calculate seasonal relevance multiplier
(define-private (get-seasonal-relevance-multiplier (season uint))
  (if (is-eq season (var-get current-season))
    u2  ;; Current season gets 2x multiplier
    u1  ;; Other seasons get base multiplier
  )
)

;; Calculate reward for a trend submission based on votes, season, and region
(define-private (calculate-trend-reward (trend-id uint))
  (match (map-get? trends trend-id)
    trend (let (
      (base-reward BASE-TREND-SUBMISSION-REWARD)
      (vote-bonus (/ (get votes trend) u10))  ;; 0.1 token per vote
      (seasonal-multiplier (get-seasonal-relevance-multiplier (get season trend)))
    )
      (* (+ base-reward vote-bonus) seasonal-multiplier)
    )
    u0  ;; Default to 0 if trend not found
  )
)

;; Generate a new unique trend ID
(define-private (generate-trend-id)
  (let ((current-id (var-get last-trend-id)))
    (var-set last-trend-id (+ current-id u1))
    (+ current-id u1)
  )
)

;; Check if a season is valid
(define-private (is-valid-season (season uint))
  (or 
    (is-eq season SEASON-SPRING)
    (is-eq season SEASON-SUMMER)
    (is-eq season SEASON-FALL)
    (is-eq season SEASON-WINTER)
  )
)

;; Check if a region is valid
(define-private (is-valid-region (region uint))
  (and (>= region REGION-NORTH-AMERICA) (<= region REGION-OCEANIA))
)

;; Helper function to check if contract is enabled
(define-private (assert-contract-enabled)
  (if (var-get contract-enabled)
    (ok true)
    ERR-CONTRACT-NOT-ENABLED
  )
)

;; Helper function to check if caller is admin
(define-private (assert-is-admin)
  (if (is-eq tx-sender ADMIN-ADDRESS)
    (ok true)
    ERR-NOT-AUTHORIZED
  )
)

;; Read-Only Functions

;; Get token URI for metadata
(define-read-only (get-token-uri (token-id uint))
  (ok (some (concat TOKEN-URI (uint-to-ascii token-id))))
)

;; Get the balance of a token for a user
(define-read-only (get-token-balance (owner principal) (token-id uint))
  (ok (get-balance owner token-id))
)

;; Get token supply
(define-read-only (get-token-supply (token-id uint))
  (ok (default-to u0 (map-get? token-supplies token-id)))
)

;; Get trend details
(define-read-only (get-trend (trend-id uint))
  (match (map-get? trends trend-id)
    trend (ok trend)
    ERR-TREND-NOT-FOUND
  )
)

;; Check if a user has voted on a specific trend
(define-read-only (has-voted (trend-id uint) (voter principal))
  (default-to false (map-get? trend-votes {trend-id: trend-id, voter: voter}))
)

;; Get current season
(define-read-only (get-current-season)
  (var-get current-season)
)

;; Public Functions

;; Submit a new trend and earn base rewards
(define-public (submit-trend (title (string-ascii 50)) (season uint) (region uint))
  (begin
    ;; Ensure contract is enabled
    (try! (assert-contract-enabled))
    
    ;; Validate inputs
    (if (not (is-valid-season season))
      ERR-INVALID-SEASON
      (if (not (is-valid-region region))
        ERR-INVALID-REGION
        (let (
          (trend-id (generate-trend-id))
        )
          ;; Store the new trend
          (map-set trends trend-id {
            submitted-by: tx-sender,
            votes: u0,
            season: season,
            region: region,
            title: title,
            rewarded: false
          })
          
          ;; Mint base reward tokens to submitter
          (try! (mint-tokens tx-sender FASHION-INFLUENCE-POINTS-ID BASE-TREND-SUBMISSION-REWARD))
          
          ;; Return the new trend ID
          (ok trend-id)
        )
      )
    )
  )
)

;; Vote on a trend and earn voting rewards
(define-public (vote-on-trend (trend-id uint))
  (begin
    ;; Ensure contract is enabled
    (try! (assert-contract-enabled))
    
    ;; Check if trend exists
    (match (map-get? trends trend-id)
      trend (begin
        ;; Check if user already voted
        (if (has-voted trend-id tx-sender)
          ERR-ALREADY-VOTED
          (let (
            (updated-votes (+ (get votes trend) u1))
            (updated-trend (merge trend {votes: updated-votes}))
          )
            ;; Update trend with new vote count
            (map-set trends trend-id updated-trend)
            
            ;; Record that this user voted on this trend
            (map-set trend-votes {trend-id: trend-id, voter: tx-sender} true)
            
            ;; Mint voting reward tokens to voter
            (try! (mint-tokens tx-sender FASHION-INFLUENCE-POINTS-ID BASE-VOTE-REWARD))
            
            (ok updated-votes)
          )
        )
      )
      ERR-INVALID-TREND
    )
  )
)

;; Claim rewards for a trend based on its performance
(define-public (claim-trend-rewards (trend-id uint))
  (begin
    ;; Ensure contract is enabled
    (try! (assert-contract-enabled))
    
    ;; Check if trend exists and was submitted by sender
    (match (map-get? trends trend-id)
      trend (begin
        ;; Verify sender is the trend submitter
        (if (not (is-eq tx-sender (get submitted-by trend)))
          ERR-NOT-AUTHORIZED
          ;; Check if rewards were already claimed
          (if (get rewarded trend)
            (ok u0)  ;; Already rewarded
            (let (
              (reward-amount (calculate-trend-reward trend-id))
              (updated-trend (merge trend {rewarded: true}))
            )
              ;; Update trend to mark as rewarded
              (map-set trends trend-id updated-trend)
              
              ;; Mint reward tokens
              (try! (mint-tokens tx-sender FASHION-INFLUENCE-POINTS-ID reward-amount))
              
              (ok reward-amount)
            )
          )
        )
      )
      ERR-TREND-NOT-FOUND
    )
  )
)

;; Spend tokens to boost a trend's visibility (implementation placeholder)
(define-public (boost-trend (trend-id uint))
  (begin
    ;; Ensure contract is enabled
    (try! (assert-contract-enabled))
    
    ;; Check if trend exists
    (match (map-get? trends trend-id)
      trend (begin
        ;; Burn tokens from sender to boost the trend
        (try! (burn-tokens tx-sender FASHION-INFLUENCE-POINTS-ID TREND-BOOST-COST))
        
        ;; Implementation of boosting logic would go here
        ;; For now, we just acknowledge the boost happened
        (ok true)
      )
      ERR-TREND-NOT-FOUND
    )
  )
)

;; Spend tokens to access premium analytics (implementation placeholder)
(define-public (access-premium-analytics)
  (begin
    ;; Ensure contract is enabled
    (try! (assert-contract-enabled))
    
    ;; Burn tokens from sender to access analytics
    (try! (burn-tokens tx-sender FASHION-INFLUENCE-POINTS-ID ANALYTICS-ACCESS-COST))
    
    ;; Implementation of analytics access would go here
    ;; For now, we just acknowledge the access was granted
    (ok true)
  )
)

;; Transfer tokens between users
(define-public (transfer (token-id uint) (amount uint) (sender principal) (recipient principal))
  (begin
    ;; Ensure contract is enabled
    (try! (assert-contract-enabled))
    
    ;; Check that sender is tx-sender or that tx-sender is approved
    (if (not (is-eq tx-sender sender))
      ERR-NOT-AUTHORIZED
      (let (
        (sender-balance (get-balance sender token-id))
      )
        ;; Check if sender has enough balance
        (if (< sender-balance amount)
          ERR-NOT-ENOUGH-TOKENS
          (begin
            ;; Update sender balance
            (map-set token-balances {owner: sender, token-id: token-id} 
              (- sender-balance amount))
            
            ;; Update recipient balance
            (map-set token-balances {owner: recipient, token-id: token-id} 
              (+ (get-balance recipient token-id) amount))
            
            (ok true)
          )
        )
      )
    )
  )
)

;; Admin Functions

;; Update the current season
(define-public (update-current-season (new-season uint))
  (begin
    ;; Ensure caller is admin
    (try! (assert-is-admin))
    
    ;; Validate season
    (if (not (is-valid-season new-season))
      ERR-INVALID-SEASON
      (begin
        (var-set current-season new-season)
        (ok true)
      )
    )
  )
)

;; Enable or disable contract functionality
(define-public (set-contract-enabled (enabled bool))
  (begin
    ;; Ensure caller is admin
    (try! (assert-is-admin))
    
    (var-set contract-enabled enabled)
    (ok true)
  )
)

;; Mint tokens as admin (for special events, etc.)
(define-public (admin-mint (recipient principal) (token-id uint) (amount uint))
  (begin
    ;; Ensure caller is admin
    (try! (assert-is-admin))
    
    ;; Don't allow minting 0 tokens
    (if (<= amount u0)
      ERR-INVALID-AMOUNT
      (mint-tokens recipient token-id amount)
    )
  )
)