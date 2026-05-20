// Cassette
// Copyright (C) 2026 Mathieu Dubart
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import Foundation

nonisolated struct ConnectionErrorPresentation: Sendable, Equatable {
    let title: LocalizedStringResource
    let description: LocalizedStringResource
    let technicalCode: String
}
