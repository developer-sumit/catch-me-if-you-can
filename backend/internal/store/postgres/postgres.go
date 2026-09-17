package postgres

import (
	"context"
	"errors"
	"fmt"
	"math"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/soulserve/soulserve/backend/internal/domain"
)

var ErrNotFound = errors.New("not found")
var ErrConflict = errors.New("conflict")

type Store struct{ pool *pgxpool.Pool }

func New(ctx context.Context, url string) (*Store, error) {
	p, err := pgxpool.New(ctx, url)
	if err != nil {
		return nil, err
	}
	if err = p.Ping(ctx); err != nil {
		p.Close()
		return nil, err
	}
	return &Store{pool: p}, nil
}
func (s *Store) Close()                           { s.pool.Close() }
func (s *Store) Health(ctx context.Context) error { return s.pool.Ping(ctx) }

const userCols = `id,name,email,password_hash,role,organization,phone,address,latitude,longitude,created_at`

const claimCols = `id,waste_log_id,ngo_id,kitchen_id,status,claimed_at,picked_up_at,out_for_delivery_at,completed_at`

// The timestamp each stage stamps when a claim reaches it.
var claimStageColumn = map[string]string{
	domain.ClaimPickedUp:       "picked_up_at",
	domain.ClaimOutForDelivery: "out_for_delivery_at",
	domain.ClaimCompleted:      "completed_at",
}

func scanClaim(row pgx.Row, c *domain.Claim) error {
	return row.Scan(&c.ID, &c.WasteLogID, &c.NGOID, &c.KitchenID, &c.Status,
		&c.ClaimedAt, &c.PickedUpAt, &c.OutForDeliveryAt, &c.CompletedAt)
}

func scanUser(row pgx.Row) (domain.User, error) {
	var u domain.User
	err := row.Scan(&u.ID, &u.Name, &u.Email, &u.PasswordHash, &u.Role, &u.Organization, &u.Phone, &u.Address, &u.Latitude, &u.Longitude, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrNotFound
	}
	return u, err
}

func (s *Store) CreateUser(ctx context.Context, u domain.User) (domain.User, error) {
	q := `INSERT INTO users(name,email,password_hash,role,organization,phone,address,latitude,longitude) VALUES($1,lower($2),$3,$4,$5,$6,$7,$8,$9) RETURNING ` + userCols
	u, err := scanUser(s.pool.QueryRow(ctx, q, u.Name, u.Email, u.PasswordHash, u.Role, u.Organization, u.Phone, u.Address, u.Latitude, u.Longitude))
	if err != nil && isUnique(err) {
		return u, ErrConflict
	}
	return u, err
}
func (s *Store) UserByEmail(ctx context.Context, email string) (domain.User, error) {
	return scanUser(s.pool.QueryRow(ctx, `SELECT `+userCols+` FROM users WHERE email=lower($1)`, email))
}
func (s *Store) UserByID(ctx context.Context, id string) (domain.User, error) {
	return scanUser(s.pool.QueryRow(ctx, `SELECT `+userCols+` FROM users WHERE id=$1`, id))
}

func scanWaste(row pgx.Row) (domain.WasteLog, error) {
	var w domain.WasteLog
	err := row.Scan(&w.ID, &w.KitchenID, &w.FoodType, &w.Quantity, &w.Unit, &w.Status, &w.ClaimedBy, &w.Notes, &w.LogDate, &w.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrNotFound
	}
	return w, err
}

const wasteCols = `id,kitchen_id,food_type,quantity,unit,status,claimed_by,notes,log_date,created_at`

func (s *Store) CreateWaste(ctx context.Context, w domain.WasteLog) (domain.WasteLog, error) {
	return scanWaste(s.pool.QueryRow(ctx, `INSERT INTO waste_logs(kitchen_id,food_type,quantity,unit,notes) VALUES($1,$2,$3,$4,$5) RETURNING `+wasteCols, w.KitchenID, w.FoodType, w.Quantity, w.Unit, w.Notes))
}
func (s *Store) WasteByID(ctx context.Context, id string) (domain.WasteLog, error) {
	return scanWaste(s.pool.QueryRow(ctx, `SELECT `+wasteCols+` FROM waste_logs WHERE id=$1`, id))
}

func (s *Store) WasteForKitchen(ctx context.Context, id string) ([]domain.WasteLog, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+joinPrefix(wasteCols, "w")+`,u.id,u.name,u.email,u.role,u.organization,u.phone,u.address,u.latitude,u.longitude,u.created_at FROM waste_logs w LEFT JOIN users u ON u.id=w.claimed_by WHERE w.kitchen_id=$1 ORDER BY w.created_at DESC`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []domain.WasteLog
	for rows.Next() {
		var w domain.WasteLog
		var u domain.User
		var uid, name, email, role, org, phone, address *string
		var lat, lng *float64
		var created *time.Time
		err = rows.Scan(&w.ID, &w.KitchenID, &w.FoodType, &w.Quantity, &w.Unit, &w.Status, &w.ClaimedBy, &w.Notes, &w.LogDate, &w.CreatedAt, &uid, &name, &email, &role, &org, &phone, &address, &lat, &lng, &created)
		if err != nil {
			return nil, err
		}
		if uid != nil {
			u.ID = *uid
			u.Name = val(name)
			u.Email = val(email)
			u.Role = domain.Role(val(role))
			u.Organization = val(org)
			u.Phone = val(phone)
			u.Address = val(address)
			u.Latitude = lat
			u.Longitude = lng
			if created != nil {
				u.CreatedAt = *created
			}
			w.Claimer = &u
		}
		out = append(out, w)
	}
	return out, rows.Err()
}

func (s *Store) AvailableWaste(ctx context.Context) ([]domain.WasteLog, error) {
	q := `SELECT ` + joinPrefix(wasteCols, "w") + `,` + joinPrefix(userCols, "u") + ` FROM waste_logs w JOIN users u ON u.id=w.kitchen_id WHERE w.status='pending' ORDER BY w.created_at DESC`
	rows, err := s.pool.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []domain.WasteLog
	for rows.Next() {
		var w domain.WasteLog
		var u domain.User
		if err := rows.Scan(&w.ID, &w.KitchenID, &w.FoodType, &w.Quantity, &w.Unit, &w.Status, &w.ClaimedBy, &w.Notes, &w.LogDate, &w.CreatedAt, &u.ID, &u.Name, &u.Email, &u.PasswordHash, &u.Role, &u.Organization, &u.Phone, &u.Address, &u.Latitude, &u.Longitude, &u.CreatedAt); err != nil {
			return nil, err
		}
		w.Kitchen = &u
		out = append(out, w)
	}
	return out, rows.Err()
}

func (s *Store) CreateClaim(ctx context.Context, wasteID, ngoID string) (domain.Claim, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return domain.Claim{}, err
	}
	defer tx.Rollback(ctx)
	var kitchenID string
	err = tx.QueryRow(ctx, `UPDATE waste_logs SET status='claimed',claimed_by=$2,claimed_at=now(),updated_at=now() WHERE id=$1 AND status='pending' RETURNING kitchen_id`, wasteID, ngoID).Scan(&kitchenID)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Claim{}, ErrConflict
	}
	if err != nil {
		return domain.Claim{}, err
	}
	var c domain.Claim
	err = scanClaim(tx.QueryRow(ctx, `INSERT INTO claims(waste_log_id,ngo_id,kitchen_id) VALUES($1,$2,$3) RETURNING `+claimCols, wasteID, ngoID, kitchenID), &c)
	if err != nil {
		return c, err
	}
	if err = tx.Commit(ctx); err != nil {
		return c, err
	}
	return c, nil
}

// AdvanceClaim moves a claim forward to target. The update is guarded by the
// set of stages target may be reached from, so a stale client cannot walk a
// delivery backwards or re-stamp a stage it already passed.
func (s *Store) AdvanceClaim(ctx context.Context, id, ngoID, target string) (domain.Claim, error) {
	column, ok := claimStageColumn[target]
	from := domain.ClaimStagesBefore(target)
	if !ok || len(from) == 0 {
		return domain.Claim{}, ErrNotFound
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return domain.Claim{}, err
	}
	defer tx.Rollback(ctx)
	var c domain.Claim
	q := fmt.Sprintf(`UPDATE claims SET status=$3,%s=now() WHERE id=$1 AND ngo_id=$2 AND status=ANY($4) RETURNING `+claimCols, column)
	err = scanClaim(tx.QueryRow(ctx, q, id, ngoID, target, from), &c)
	if errors.Is(err, pgx.ErrNoRows) {
		return c, ErrNotFound
	}
	if err != nil {
		return c, err
	}
	// The donation is only spent once it has actually been handed over.
	if target == domain.ClaimCompleted {
		if _, err = tx.Exec(ctx, `UPDATE waste_logs SET status='completed',updated_at=now() WHERE id=$1`, c.WasteLogID); err != nil {
			return c, err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return c, err
	}
	return c, nil
}
func (s *Store) ClaimsForNGO(ctx context.Context, id string) ([]domain.Claim, error) {
	q := `SELECT ` + joinPrefix(claimCols, "c") + `,` + joinPrefix(wasteCols, "w") + `,` + joinPrefix(userCols, "u") + ` FROM claims c JOIN waste_logs w ON w.id=c.waste_log_id JOIN users u ON u.id=c.kitchen_id WHERE c.ngo_id=$1 ORDER BY c.claimed_at DESC`
	rows, err := s.pool.Query(ctx, q, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []domain.Claim
	for rows.Next() {
		var c domain.Claim
		var w domain.WasteLog
		var u domain.User
		if err = rows.Scan(&c.ID, &c.WasteLogID, &c.NGOID, &c.KitchenID, &c.Status, &c.ClaimedAt, &c.PickedUpAt, &c.OutForDeliveryAt, &c.CompletedAt, &w.ID, &w.KitchenID, &w.FoodType, &w.Quantity, &w.Unit, &w.Status, &w.ClaimedBy, &w.Notes, &w.LogDate, &w.CreatedAt, &u.ID, &u.Name, &u.Email, &u.PasswordHash, &u.Role, &u.Organization, &u.Phone, &u.Address, &u.Latitude, &u.Longitude, &u.CreatedAt); err != nil {
			return nil, err
		}
		c.WasteLog = &w
		c.Kitchen = &u
		out = append(out, c)
	}
	return out, rows.Err()
}
func (s *Store) KitchenStats(ctx context.Context, id string) (domain.KitchenStats, error) {
	var x domain.KitchenStats
	err := s.pool.QueryRow(ctx, `SELECT count(*),coalesce(sum(quantity),0),count(*) FILTER(WHERE status='claimed'),count(*) FILTER(WHERE status='completed'),count(*) FILTER(WHERE status='pending'),coalesce(sum(quantity) FILTER(WHERE status IN ('claimed','completed')),0) FROM waste_logs WHERE kitchen_id=$1`, id).Scan(&x.TotalLogged, &x.TotalQuantity, &x.TotalClaimed, &x.TotalCompleted, &x.TotalPending, &x.RedistributedQuantity)
	if err != nil {
		return x, err
	}
	rows, err := s.pool.Query(ctx, `SELECT food_type,sum(quantity) FROM waste_logs WHERE kitchen_id=$1 GROUP BY food_type ORDER BY sum(quantity) DESC`, id)
	if err != nil {
		return x, err
	}
	defer rows.Close()
	for rows.Next() {
		var f domain.FoodTotal
		if err = rows.Scan(&f.FoodType, &f.Total); err != nil {
			return x, err
		}
		x.ByType = append(x.ByType, f)
	}
	return x, rows.Err()
}
func (s *Store) NGOStats(ctx context.Context, id string) (domain.NGOStats, error) {
	var x domain.NGOStats
	err := s.pool.QueryRow(ctx, `SELECT count(*),count(*) FILTER(WHERE c.status='completed'),coalesce(sum(w.quantity) FILTER(WHERE c.status='completed'),0) FROM claims c JOIN waste_logs w ON w.id=c.waste_log_id WHERE c.ngo_id=$1`, id).Scan(&x.TotalClaimed, &x.TotalCompleted, &x.TotalQuantitySaved)
	return x, err
}
func (s *Store) History(ctx context.Context, id string, days int) ([]domain.WasteLog, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+wasteCols+` FROM waste_logs WHERE kitchen_id=$1 AND log_date>=current_date-$2::int ORDER BY log_date`, id, days)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []domain.WasteLog
	for rows.Next() {
		w, e := scanWaste(rows)
		if e != nil {
			return nil, e
		}
		out = append(out, w)
	}
	return out, rows.Err()
}

func DistanceKM(aLat, aLng, bLat, bLng float64) float64 {
	const r = 6371.
	dLat := (bLat - aLat) * math.Pi / 180
	dLng := (bLng - aLng) * math.Pi / 180
	a := math.Sin(dLat/2)*math.Sin(dLat/2) + math.Cos(aLat*math.Pi/180)*math.Cos(bLat*math.Pi/180)*math.Sin(dLng/2)*math.Sin(dLng/2)
	return r * 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
}
func isUnique(err error) bool {
	return err != nil && (fmt.Sprint(err) != "") && contains(fmt.Sprint(err), "23505")
}
func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
func val(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
func joinPrefix(cols, p string) string {
	out := ""
	start := 0
	for i := 0; i <= len(cols); i++ {
		if i == len(cols) || cols[i] == ',' {
			if out != "" {
				out += ","
			}
			out += p + "." + cols[start:i]
			start = i + 1
		}
	}
	return out
}
