#include <iostream>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

int main()
{
    // Create a JSON object
    json j = {
        {"name", "John Doe"},
        {"age", 30},
        {"city", "New York"},
        {"hobbies", {"reading", "hiking", "photography"}}
    };

    // Print the JSON object
    std::cout << "JSON object:\n" << j.dump(4) << std::endl;

    // Access values
    std::cout << "\nName: " << j["name"] << std::endl;
    std::cout << "Age: " << j["age"] << std::endl;
    std::cout << "First hobby: " << j["hobbies"][0] << std::endl;

    return 0;
} 