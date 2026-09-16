/* Nix has no shift operator, so << and >> go through a power-of-two table.
   The right shift of a NEGATIVE value is the one that separates an
   arithmetic shift from a division truncating toward zero: -1 >> 1 is -1,
   while -1 / 2 is 0. */
#if (1 << 4) == 16 && (3 << 3) == 24
int shift_left = 1;
#else
int shift_left_wrong = 1;
#endif

#if (256 >> 4) == 16 && (7 >> 1) == 3
int shift_right = 2;
#else
int shift_right_wrong = 2;
#endif

#if (-1 >> 1) == -1 && (-16 >> 2) == -4 && (-7 >> 1) == -4
int arithmetic_shift = 3;
#else
int arithmetic_shift_wrong = 3;
#endif

#if 1 << 2 + 1 == 8
int shift_binds_loose = 4;
#else
int shift_binds_loose_wrong = 4;
#endif

#if (1 << 0) == 1 && (5 << 1 >> 1) == 5
int shift_edges = 5;
#else
int shift_edges_wrong = 5;
#endif

/* `1 << 31' is where a 32-bit #if and a 64-bit one part company: C89 6.8.1
   evaluates in long, which is 4 bytes on this target, so the result is
   negative here and positive under gcc's intmax_t. That divergence is pinned
   in cases.nix, where there is no second implementation to disagree with. */
