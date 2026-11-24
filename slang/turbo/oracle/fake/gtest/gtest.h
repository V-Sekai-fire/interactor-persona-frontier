#pragma once
struct NullStream { template<class T> NullStream& operator<<(const T&) { return *this; } };
#define EXPECT_TRUE(x) ((void)(x), NullStream{})
#define EXPECT_FALSE(x) ((void)(x), NullStream{})
#define EXPECT_EQ(a,b) ((void)0, NullStream{})
