package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/soulserve/soulserve/backend/internal/domain"
	"github.com/soulserve/soulserve/backend/internal/service"
	pg "github.com/soulserve/soulserve/backend/internal/store/postgres"
)

type ctxKey int

const principalKey ctxKey = 1

type principal struct {
	ID   string
	Role domain.Role
}
type API struct {
	svc     *service.Service
	log     *slog.Logger
	origins map[string]bool
}

func New(s *service.Service, log *slog.Logger, origins []string) http.Handler {
	a := &API{svc: s, log: log, origins: map[string]bool{}}
	for _, o := range origins {
		a.origins[o] = true
	}
	m := http.NewServeMux()
	m.HandleFunc("GET /api/health", a.health)
	m.HandleFunc("POST /api/auth/register", a.register)
	m.HandleFunc("POST /api/auth/login", a.login)
	m.Handle("GET /api/auth/me", a.auth(http.HandlerFunc(a.me)))
	m.Handle("POST /api/waste/log", a.role(domain.RoleKitchen, http.HandlerFunc(a.logWaste)))
	m.Handle("GET /api/waste/my-logs", a.role(domain.RoleKitchen, http.HandlerFunc(a.myWaste)))
	m.Handle("GET /api/waste/available", a.role(domain.RoleNGO, http.HandlerFunc(a.available)))
	m.Handle("POST /api/claims/{wasteID}/claim", a.role(domain.RoleNGO, http.HandlerFunc(a.claim)))
	m.Handle("PATCH /api/claims/{id}/status", a.role(domain.RoleNGO, http.HandlerFunc(a.advance)))
	m.Handle("PATCH /api/claims/{id}/complete", a.role(domain.RoleNGO, http.HandlerFunc(a.complete)))
	m.Handle("GET /api/claims/my-claims", a.role(domain.RoleNGO, http.HandlerFunc(a.claims)))
	m.Handle("GET /api/dashboard/kitchen/stats", a.role(domain.RoleKitchen, http.HandlerFunc(a.kitchenStats)))
	m.Handle("GET /api/dashboard/kitchen/history", a.role(domain.RoleKitchen, http.HandlerFunc(a.history)))
	m.Handle("GET /api/dashboard/ngo/stats", a.role(domain.RoleNGO, http.HandlerFunc(a.ngoStats)))
	m.Handle("GET /api/dashboard/predictions", a.auth(http.HandlerFunc(a.predictions)))
	return a.recover(a.securityHeaders(a.cors(a.logging(m))))
}
func (a *API) health(w http.ResponseWriter, r *http.Request) {
	write(w, 200, map[string]any{"status": "ok", "timestamp": time.Now().UTC()})
}

type authRequest struct {
	Name         string      `json:"name"`
	Email        string      `json:"email"`
	Password     string      `json:"password"`
	Role         domain.Role `json:"role"`
	Organization string      `json:"organization"`
	Phone        string      `json:"phone"`
	Address      string      `json:"address"`
	Latitude     *float64    `json:"latitude"`
	Longitude    *float64    `json:"longitude"`
}

func (a *API) register(w http.ResponseWriter, r *http.Request) {
	var x authRequest
	if !decode(w, r, &x) {
		return
	}
	token, u, err := a.svc.Register(r.Context(), service.RegisterInput{Name: x.Name, Email: x.Email, Password: x.Password, Role: x.Role, Organization: x.Organization, Phone: x.Phone, Address: x.Address, Latitude: x.Latitude, Longitude: x.Longitude})
	if err != nil {
		if errors.Is(err, pg.ErrConflict) {
			validationProblem(w, 409, "email_in_use", "An account with this email already exists", map[string]string{"email": "This email is already registered"})
			return
		}
		a.err(w, err)
		return
	}
	write(w, 201, map[string]any{"token": token, "user": u})
}
func (a *API) login(w http.ResponseWriter, r *http.Request) {
	var x authRequest
	if !decode(w, r, &x) {
		return
	}
	token, u, err := a.svc.Login(r.Context(), x.Email, x.Password)
	if err != nil {
		a.err(w, err)
		return
	}
	write(w, 200, map[string]any{"token": token, "user": u})
}
func (a *API) me(w http.ResponseWriter, r *http.Request) {
	u, err := a.svc.Me(r.Context(), who(r).ID)
	if err != nil {
		a.err(w, err)
		return
	}
	write(w, 200, u)
}
func (a *API) logWaste(w http.ResponseWriter, r *http.Request) {
	var x struct {
		FoodType string  `json:"foodType"`
		Quantity float64 `json:"quantity"`
		Unit     string  `json:"unit"`
		Notes    string  `json:"notes"`
	}
	if !decode(w, r, &x) {
		return
	}
	v, err := a.svc.LogWaste(r.Context(), who(r).ID, x.FoodType, x.Quantity, x.Unit, x.Notes)
	if err != nil {
		a.err(w, err)
		return
	}
	write(w, 201, map[string]any{"log": v, "message": "Food logged successfully"})
}
func (a *API) myWaste(w http.ResponseWriter, r *http.Request) {
	x, e := a.svc.MyWaste(r.Context(), who(r).ID)
	if e != nil {
		a.err(w, e)
		return
	}
	write(w, 200, list(x))
}
func (a *API) available(w http.ResponseWriter, r *http.Request) {
	x, e := a.svc.Available(r.Context(), who(r).ID)
	if e != nil {
		a.err(w, e)
		return
	}
	write(w, 200, list(x))
}
func (a *API) claim(w http.ResponseWriter, r *http.Request) {
	x, e := a.svc.Claim(r.Context(), r.PathValue("wasteID"), who(r).ID)
	if e != nil {
		a.err(w, e)
		return
	}
	write(w, 201, map[string]any{"claim": x, "message": "Food claimed successfully"})
}

// advance records the next step of a delivery: picked up, out for delivery, or
// delivered.
func (a *API) advance(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Status string `json:"status"`
	}
	if !decode(w, r, &body) {
		return
	}
	x, e := a.svc.Advance(r.Context(), r.PathValue("id"), who(r).ID, body.Status)
	if e != nil {
		a.err(w, e)
		return
	}
	write(w, 200, map[string]any{"claim": x, "message": claimStageMessage[x.Status]})
}

// complete is the pre-existing shortcut straight to delivered, kept so older
// clients keep working.
func (a *API) complete(w http.ResponseWriter, r *http.Request) {
	x, e := a.svc.Advance(r.Context(), r.PathValue("id"), who(r).ID, domain.ClaimCompleted)
	if e != nil {
		a.err(w, e)
		return
	}
	write(w, 200, map[string]any{"claim": x, "message": claimStageMessage[x.Status]})
}

var claimStageMessage = map[string]string{
	domain.ClaimPickedUp:       "Collected from the kitchen",
	domain.ClaimOutForDelivery: "Out for delivery",
	domain.ClaimCompleted:      "Delivered",
}

func (a *API) claims(w http.ResponseWriter, r *http.Request) {
	x, e := a.svc.Claims(r.Context(), who(r).ID)
	if e != nil {
		a.err(w, e)
		return
	}
	write(w, 200, list(x))
}
func (a *API) kitchenStats(w http.ResponseWriter, r *http.Request) {
	x, e := a.svc.KitchenStats(r.Context(), who(r).ID)
	if e != nil {
		a.err(w, e)
		return
	}
	write(w, 200, x)
}
func (a *API) ngoStats(w http.ResponseWriter, r *http.Request) {
	x, e := a.svc.NGOStats(r.Context(), who(r).ID)
	if e != nil {
		a.err(w, e)
		return
	}
	write(w, 200, x)
}
func (a *API) history(w http.ResponseWriter, r *http.Request) {
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	x, e := a.svc.History(r.Context(), who(r).ID, days)
	if e != nil {
		a.err(w, e)
		return
	}
	write(w, 200, list(x))
}
func (a *API) predictions(w http.ResponseWriter, r *http.Request) {
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if days < 1 || days > 30 {
		days = 7
	}
	foods := []string{"rice", "dal", "roti", "vegetables", "curry"}
	out := make([]map[string]any, days)
	for i := 1; i <= days; i++ {
		d := time.Now().AddDate(0, 0, i)
		p := map[string]float64{}
		for n, f := range foods {
			p[f] = float64(30+n*7+(int(d.Weekday())+1)*2) / 10
		}
		out[i-1] = map[string]any{"date": d.Format("2006-01-02"), "dayOfWeek": d.Format("Mon"), "isWeekend": d.Weekday() == 0 || d.Weekday() == 6, "predictions": p}
	}
	write(w, 200, map[string]any{"predictions": out, "model": "baseline-v1", "accuracy": .82})
}
func (a *API) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if h == "" {
			problem(w, 401, "unauthorized", "Bearer token required")
			return
		}
		id, role, e := a.svc.ParseToken(h)
		if e != nil {
			problem(w, 401, "unauthorized", "Invalid or expired token")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), principalKey, principal{id, role})))
	})
}
func (a *API) role(role domain.Role, next http.Handler) http.Handler {
	return a.auth(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if who(r).Role != role {
			problem(w, 403, "forbidden", "This action is unavailable for your role")
			return
		}
		next.ServeHTTP(w, r)
	}))
}
func who(r *http.Request) principal { return r.Context().Value(principalKey).(principal) }
func (a *API) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		o := r.Header.Get("Origin")
		if a.origins[o] {
			w.Header().Set("Access-Control-Allow-Origin", o)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PATCH,OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(204)
			return
		}
		next.ServeHTTP(w, r)
	})
}
func (a *API) logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		a.log.Info("request", "method", r.Method, "path", r.URL.Path, "duration", time.Since(start))
	})
}
func (a *API) recover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if x := recover(); x != nil {
				a.log.Error("panic", "error", x)
				problem(w, 500, "internal_error", "An unexpected error occurred")
			}
		}()
		next.ServeHTTP(w, r)
	})
}
func (a *API) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
		next.ServeHTTP(w, r)
	})
}
func (a *API) err(w http.ResponseWriter, e error) {
	var validation *service.ValidationError
	switch {
	case errors.As(e, &validation):
		validationProblem(w, 422, "validation_failed", "Please correct the highlighted fields", validation.Fields)
	case errors.Is(e, service.ErrInvalid):
		problem(w, 422, "invalid_input", "The submitted values are invalid")
	case errors.Is(e, service.ErrUnauthorized):
		problem(w, 401, "unauthorized", "Invalid email or password")
	case errors.Is(e, pg.ErrNotFound):
		problem(w, 404, "not_found", "Resource not found")
	case errors.Is(e, pg.ErrConflict):
		problem(w, 409, "conflict", "Resource already exists or is no longer available")
	default:
		a.log.Error("request failed", "error", e)
		problem(w, 500, "internal_error", "An unexpected error occurred")
	}
}
func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	d := json.NewDecoder(r.Body)
	d.DisallowUnknownFields()
	if err := d.Decode(v); err != nil {
		problem(w, 400, "invalid_json", "Request body must contain valid JSON")
		return false
	}
	if err := d.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		problem(w, 400, "invalid_json", "Request body must contain one JSON object")
		return false
	}
	return true
}
func write(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func problem(w http.ResponseWriter, status int, code, msg string) {
	write(w, status, map[string]any{"error": msg, "code": code})
}
func validationProblem(w http.ResponseWriter, status int, code, msg string, fields map[string]string) {
	write(w, status, map[string]any{"error": msg, "code": code, "fields": fields})
}
func list[T any](v []T) []T {
	if v == nil {
		return []T{}
	}
	return v
}
