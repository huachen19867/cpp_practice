// 简单的 C++ 入门示例：编译后会在控制台输出内容
#include <iostream>
#include <string>
#include "math_utils.h"

int main() {
    std::cout << "你好，C++！这是你的第一个 Trae 示例。\n";

    int x = 2;
    int y = 3;
    std::cout << "2 + 3 = " << add(x, y) << "\n";
    std::vector<int> data = {1, 2, 3, 4, 5};
    std::cout << "平均值 = " << average(data) << "\n";

    std::string name;
    std::cout << "输入你的名字并按回车：";
    std::getline(std::cin, name);
    std::cout << "很高兴认识你，" << name << "！\n";

    return 0;
}

