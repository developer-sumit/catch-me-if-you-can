package service

import (
	"context"
	"errors"
	"fmt"
	"net/mail"
	"sort"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/soulserve/soulserve/backend/internal/domain"
	"github.com/soulserve/soulserve/backend/internal/store"
	pg "github.com/soulserve/soulserve/backend/internal/store/postgres"
	"golang.org/x/crypto/bcrypt"
)

var ErrUnauthorized = errors.New("invalid credentials")
var ErrInvalid = errors.New("invalid input")

type ValidationError struct {
	Fields map[string]string
}

func (e *ValidationError) Error() string { return "validation failed" }

type Service struct {
	store  store.Store
	secret []byte
	ttl    time.Duration
}

func New(st store.Store, secret string, ttl time.Duration) *Service {
	return &Service{store: st, secret: []byte(secret), ttl: ttl}
}

type RegisterInput struct {
	Name, Email, Password        string
	Role                         domain.Role
	Organization, Phone, Address string
	Latitude, Longitude          *float64
}

func (s *Service) Register(ctx context.Context, in RegisterInput) (string, domain.User, error) {
	in.Name = strings.TrimSpace(in.Name)
	in.Email = strings.ToLower(strings.TrimSpace(in.Email))
	in.Organization = strings.TrimSpace(in.Organization)
	in.Phone = strings.TrimSpace(in.Phone)
	in.Address = strings.TrimSpace(in.Address)
	if fields := validateRegistration(in); len(fields) > 0 {
		return "", domain.User{}, &ValidationError{Fields: fields}
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(in.Password), bcrypt.DefaultCost)
	if err != nil {
		return "", domain.User{}, err
	}
	u, err := s.store.CreateUser(ctx, domain.User{Name: in.Name, Email: in.Email, PasswordHash: string(hash), Role: in.Role, Organization: in.Organization, Phone: in.Phone, Address: in.Address, Latitude: in.Latitude, Longitude: in.Longitude})
	if err != nil {
		return "", u, err
	}
	token, err := s.token(u)
	return token, u, err
}
func (s *Service) Login(ctx context.Context, email, password string) (string, domain.User, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" || password == "" {
		return "", domain.User{}, &ValidationError{Fields: map[string]string{"email": "Email and password are required"}}
	}
	u, err := s.store.UserByEmail(ctx, email)
	if err != nil || bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(password)) != nil {
		return "", domain.User{}, ErrUnauthorized
	}
	token, err := s.token(u)
	return token, u, err
}
func (s *Service) token(u domain.User) (string, error) {
	now := time.Now()
	c := jwt.MapClaims{"sub": u.ID, "role": u.Role, "email": u.Email, "iss": "soulserve", "iat": now.Unix(), "nbf": now.Unix(), "exp": now.Add(s.ttl).Unix()}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString(s.secret)
}
func (s *Service) ParseToken(raw string) (string, domain.Role, error) {
	t, err := jwt.Parse(raw, func(t *jwt.Token) (any, error) {
		if t.Method != jwt.SigningMethodHS256 {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return s.secret, nil
	}, jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}), jwt.WithIssuer("soulserve"), jwt.WithExpirationRequired())
	if err != nil || !t.Valid {
		return "", "", ErrUnauthorized
	}
	c, ok := t.Claims.(jwt.MapClaims)
	if !ok {
		return "", "", ErrUnauthorized
	}
	id, _ := c["sub"].(string)
	role, _ := c["role"].(string)
	parsedRole := domain.Role(role)
	if id == "" || (parsedRole != domain.RoleKitchen && parsedRole != domain.RoleNGO) {
		return "", "", ErrUnauthorized
	}
	return id, parsedRole, nil
}
func (s *Service) Me(ctx context.Context, id string) (domain.User, error) {
	return s.store.UserByID(ctx, id)
}
func (s *Service) LogWaste(ctx context.Context, id, food string, qty float64, unit, notes string) (domain.WasteLog, error) {
	allowed := map[string]bool{"rice": true, "dal": true, "roti": true, "vegetables": true, "curry": true, "biryani": true, "bread": true, "fruits": true, "dairy": true, "other": true}
	food = strings.ToLower(strings.TrimSpace(food))
	unit = strings.ToLower(strings.TrimSpace(unit))
	notes = strings.TrimSpace(notes)
	fields := map[string]string{}
	if !allowed[food] {
		fields["foodType"] = "Choose a supported food type"
	}
	if qty <= 0 || qty > 10000 {
		fields["quantity"] = "Quantity must be greater than 0 and at most 10,000"
	}
	if unit == "" {
		unit = "kg"
	}
	if unit != "kg" {
		fields["unit"] = "Only kilograms are currently supported"
	}
	if utf8.RuneCountInString(notes) > 1000 {
		fields["notes"] = "Notes cannot exceed 1,000 characters"
	}
	if len(fields) > 0 {
		return domain.WasteLog{}, &ValidationError{Fields: fields}
	}
	return s.store.CreateWaste(ctx, domain.WasteLog{KitchenID: id, FoodType: food, Quantity: qty, Unit: unit, Notes: notes})
}
func (s *Service) MyWaste(ctx context.Context, id string) ([]domain.WasteLog, error) {
	return s.store.WasteForKitchen(ctx, id)
}
func (s *Service) Available(ctx context.Context, id string) ([]domain.WasteLog, error) {
	ngo, err := s.store.UserByID(ctx, id)
	if err != nil {
		return nil, err
	}
	logs, err := s.store.AvailableWaste(ctx)
	if err != nil {
		return nil, err
	}
	if ngo.Latitude != nil && ngo.Longitude != nil {
		for i := range logs {
			if logs[i].Kitchen != nil && logs[i].Kitchen.Latitude != nil && logs[i].Kitchen.Longitude != nil {
				d := pg.DistanceKM(*ngo.Latitude, *ngo.Longitude, *logs[i].Kitchen.Latitude, *logs[i].Kitchen.Longitude)
				logs[i].DistanceKM = &d
			}
		}
		sort.SliceStable(logs, func(i, j int) bool {
			if logs[i].DistanceKM == nil {
				return false
			}
			if logs[j].DistanceKM == nil {
				return true
			}
			return *logs[i].DistanceKM < *logs[j].DistanceKM
		})
	}
	return logs, nil
}
func (s *Service) Claim(ctx context.Context, wasteID, ngoID string) (domain.Claim, error) {
	if _, err := uuid.Parse(wasteID); err != nil {
		return domain.Claim{}, &ValidationError{Fields: map[string]string{"wasteId": "Invalid donation identifier"}}
	}
	return s.store.CreateClaim(ctx, wasteID, ngoID)
}

// Advance moves a claim to the next stage of its delivery. Only forward moves
// through domain.ClaimStages are accepted; "claimed" is set when the claim is
// created and is therefore not a valid target.
func (s *Service) Advance(ctx context.Context, claimID, ngoID, target string) (domain.Claim, error) {
	if _, err := uuid.Parse(claimID); err != nil {
		return domain.Claim{}, &ValidationError{Fields: map[string]string{"claimId": "Invalid claim identifier"}}
	}
	if len(domain.ClaimStagesBefore(target)) == 0 {
		return domain.Claim{}, &ValidationError{Fields: map[string]string{"status": "Choose picked_up, out_for_delivery, or completed"}}
	}
	return s.store.AdvanceClaim(ctx, claimID, ngoID, target)
}
func (s *Service) Claims(ctx context.Context, id string) ([]domain.Claim, error) {
	return s.store.ClaimsForNGO(ctx, id)
}

func validateRegistration(in RegisterInput) map[string]string {
	fields := map[string]string{}
	if n := utf8.RuneCountInString(in.Name); n < 2 || n > 100 {
		fields["name"] = "Enter a name between 2 and 100 characters"
	}
	address, err := mail.ParseAddress(in.Email)
	if err != nil || address.Address != in.Email || len(in.Email) > 254 {
		fields["email"] = "Enter a valid email address"
	}
	if message := passwordProblem(in.Password); message != "" {
		fields["password"] = message
	}
	if in.Role != domain.RoleKitchen && in.Role != domain.RoleNGO {
		fields["role"] = "Choose Food provider or NGO"
	}
	if n := utf8.RuneCountInString(in.Organization); n < 2 || n > 150 {
		fields["organization"] = "Enter an organization name between 2 and 150 characters"
	}
	if n := utf8.RuneCountInString(in.Address); n < 5 || n > 500 {
		fields["address"] = "Enter an address between 5 and 500 characters"
	}
	if in.Phone != "" {
		digits := 0
		for _, r := range in.Phone {
			if unicode.IsDigit(r) {
				digits++
			} else if !strings.ContainsRune("+ -()", r) {
				fields["phone"] = "Enter a valid phone number"
				break
			}
		}
		if digits < 7 || digits > 15 {
			fields["phone"] = "Phone number must contain 7 to 15 digits"
		}
	}
	if (in.Latitude == nil) != (in.Longitude == nil) {
		fields["location"] = "Provide both latitude and longitude"
	} else if in.Latitude != nil && (*in.Latitude < -90 || *in.Latitude > 90) {
		fields["latitude"] = "Latitude must be between -90 and 90"
	} else if in.Longitude != nil && (*in.Longitude < -180 || *in.Longitude > 180) {
		fields["longitude"] = "Longitude must be between -180 and 180"
	}
	return fields
}

func passwordProblem(password string) string {
	if len(password) < 10 || len(password) > 72 {
		return "Use 10 to 72 characters"
	}
	var lower, upper, digit bool
	for _, r := range password {
		lower = lower || unicode.IsLower(r)
		upper = upper || unicode.IsUpper(r)
		digit = digit || unicode.IsDigit(r)
	}
	if !lower || !upper || !digit {
		return "Include an uppercase letter, lowercase letter, and number"
	}
	return ""
}
func (s *Service) KitchenStats(ctx context.Context, id string) (domain.KitchenStats, error) {
	return s.store.KitchenStats(ctx, id)
}
func (s *Service) NGOStats(ctx context.Context, id string) (domain.NGOStats, error) {
	return s.store.NGOStats(ctx, id)
}
func (s *Service) History(ctx context.Context, id string, days int) ([]domain.WasteLog, error) {
	if days < 1 || days > 365 {
		days = 30
	}
	return s.store.History(ctx, id, days)
}
