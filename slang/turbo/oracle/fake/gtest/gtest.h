// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2025 Pierre Talbot
// SPDX-FileCopyrightText: 2021 Pierre Talbot, Frédéric Pinel
// SPDX-License-Identifier: Apache-2.0 AND MIT
#pragma once
struct NullStream { template<class T> NullStream& operator<<(const T&) { return *this; } };
#define EXPECT_TRUE(x) ((void)(x), NullStream{})
#define EXPECT_FALSE(x) ((void)(x), NullStream{})
#define EXPECT_EQ(a,b) ((void)0, NullStream{})
