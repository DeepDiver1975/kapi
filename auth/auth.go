/*
 * Copyright 2018 Kopano and its licensors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License, version 3,
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

package auth

import (
	"context"
)

type requestContextKey string

const (
	authenticatedUserIDrequestContextKey requestContextKey = "authenticatedUserID"
)

// AuthenticatedUserIDFromContext returns the provided requests authentication
// ID if present.
func AuthenticatedUserIDFromContext(ctx context.Context) (string, bool) {
	if v := ctx.Value(authenticatedUserIDrequestContextKey); v != nil {
		return v.(string), true
	}

	return "", false
}

// ContextWithAuthenticatedUserID adds the provided authenticatedUSerID to the
// provided parent context and returns a context holding the value.
func ContextWithAuthenticatedUserID(parent context.Context, authenticatedUserID string) context.Context {
	return context.WithValue(parent, authenticatedUserIDrequestContextKey, authenticatedUserID)
}
