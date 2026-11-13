#include "aerospatial_native.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

int main(int argc, char **argv) {
    if (argc == 6 && std::strcmp(argv[1], "geo") == 0) {
        const ASGeodetic a{std::strtod(argv[2], nullptr), std::strtod(argv[3], nullptr)};
        const ASGeodetic b{std::strtod(argv[4], nullptr), std::strtod(argv[5], nullptr)};
        double distance = 0, bearing = 0;
        if (as_geodesic(a, b, &distance, &bearing) != AS_OK) return 2;
        std::printf("{\"distance_m\":%.12g,\"bearing_deg\":%.12g}\n", distance, bearing);
        return 0;
    }
    if (argc == 5 && std::strcmp(argv[1], "ecef") == 0) {
        const ASGeodetic3 p{std::strtod(argv[2], nullptr), std::strtod(argv[3], nullptr),
                            std::strtod(argv[4], nullptr)};
        ASVector3 value{};
        if (as_wgs84_ecef(p, &value) != AS_OK) return 2;
        std::printf("{\"x\":%.12g,\"y\":%.12g,\"z\":%.12g}\n", value.x, value.y, value.z);
        return 0;
    }
    if (argc == 8 && std::strcmp(argv[1], "enu") == 0) {
        const ASGeodetic3 a{std::strtod(argv[2], nullptr), std::strtod(argv[3], nullptr),
                            std::strtod(argv[4], nullptr)};
        const ASGeodetic3 b{std::strtod(argv[5], nullptr), std::strtod(argv[6], nullptr),
                            std::strtod(argv[7], nullptr)};
        ASVector3 value{};
        if (as_wgs84_enu(a, b, &value) != AS_OK) return 2;
        std::printf("{\"east\":%.12g,\"north\":%.12g,\"up\":%.12g}\n", value.x, value.y, value.z);
        return 0;
    }
    std::fprintf(stderr, "Usage: aerospatial-native-probe geo lat1 lon1 lat2 lon2 | ecef lat lon height | enu lat1 lon1 h1 lat2 lon2 h2\n");
    return 2;
}
