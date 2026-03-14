#include "math_utils.h"

int add(int a, int b) {
    return a + b;
}

double average(const std::vector<int>& v) {
    if (v.empty()) return 0.0;
    long long sum = 0;
    for (int x : v) sum += x;
    return static_cast<double>(sum) / static_cast<double>(v.size());
}

