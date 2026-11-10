#include "include/aerospatial_fusion.h"
#include <array>
#include <cmath>
#include <deque>
#include <mutex>
#include <new>

namespace {
constexpr size_t kMaximumHistory = 256;
constexpr size_t kMaximumCorrectionsPerStep = 4;
constexpr double kTimeToleranceSeconds = 1e-6;

struct PositionCorrection {
    ASVector3 position{};
    double standard_deviation = 0;
    double maximum_nis = 0;
};
struct HistoryStep {
    ASInertialState state{}; // State after every correction at this timestamp.
    ASVector3 force{};
    ASVector3 gyro{};
    std::array<PositionCorrection, kMaximumCorrectionsPerStep> corrections{};
    size_t correction_count = 0;
};
}
struct ASFusion {
    mutable std::mutex lock;
    ASInertialState state{};
    ASInertialNoise noise{};
    ASFusionReport stats{};
    std::deque<HistoryStep> history;
};

namespace {
ASStatus observe(ASFusion *fusion, uint64_t sequence, double time,
                 ASVector3 position, double std, double gate, bool allow_delayed) {
    if (!fusion) return AS_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> guard(fusion->lock);
    if (!sequence || sequence <= fusion->stats.last_position_sequence ||
        !std::isfinite(time) || !fusion->stats.healthy) {
        ++fusion->stats.rejected_time;
        return AS_INVALID_ARGUMENT;
    }
    if (fusion->history.empty()) {
        ++fusion->stats.rejected_invalid;
        return AS_INVALID_ARGUMENT;
    }
    const double age = fusion->state.last_time_s - time;
    if (!std::isfinite(age) || age < -kTimeToleranceSeconds ||
        (!allow_delayed && std::abs(age) > kTimeToleranceSeconds)) {
        ++fusion->stats.rejected_time;
        return AS_INVALID_ARGUMENT;
    }
    // A delayed observation is admissible only on a retained IMU checkpoint.
    // Never interpolate an unknown source time or silently apply it to 'now'.
    size_t index = fusion->history.size();
    for (size_t i = 0; i < fusion->history.size(); ++i) {
        if (std::abs(fusion->history[i].state.last_time_s - time) <= kTimeToleranceSeconds) {
            index = i;
            break;
        }
    }
    if (index == fusion->history.size()) {
        ++fusion->stats.rejected_time;
        return AS_INVALID_ARGUMENT;
    }
    if (fusion->history[index].correction_count >= kMaximumCorrectionsPerStep) {
        ++fusion->stats.rejected_invalid;
        return AS_INVALID_ARGUMENT;
    }
    if (index + 1 == fusion->history.size()) {
        // The common current-time path is allocation-free: one ESKF update,
        // one fixed-size correction slot, and no history-wide copy.
        ASInertialState updated = fusion->state;
        double innovation = 0;
        const ASStatus status = as_inertial_update_position(&updated, position,
                                                              std, gate, &innovation);
        if (status == AS_OUTLIER_REJECTED) {
            ++fusion->stats.rejected_outlier;
            fusion->stats.last_nis = innovation;
            return status;
        }
        if (status != AS_OK) {
            ++fusion->stats.rejected_invalid;
            return status;
        }
        auto &step = fusion->history.back();
        step.corrections[step.correction_count++] = {position, std, gate};
        step.state = updated;
        fusion->state = updated;
        fusion->stats.last_nis = innovation;
        fusion->stats.last_position_sequence = sequence;
        ++fusion->stats.corrected;
        return AS_OK;
    }
    try {
        // Transactional replay: an outlier or numerical failure must not mutate
        // any later checkpoint, covariance, sequence number or current state.
        auto revised = fusion->history;
        double innovation = 0;
        ASStatus status = as_inertial_update_position(&revised[index].state, position,
                                                        std, gate, &innovation);
        if (status == AS_OUTLIER_REJECTED) {
            ++fusion->stats.rejected_outlier;
            fusion->stats.last_nis = innovation;
            return status;
        }
        if (status != AS_OK) {
            ++fusion->stats.rejected_invalid;
            return status;
        }
        auto &current = revised[index];
        current.corrections[current.correction_count++] = {position, std, gate};
        for (size_t i = index + 1; i < revised.size(); ++i) {
            auto &step = revised[i];
            ASInertialState predicted = revised[i - 1].state;
            status = as_inertial_predict(&predicted, step.state.last_time_s,
                                         step.force, step.gyro, fusion->noise);
            if (status != AS_OK) {
                ++fusion->stats.rejected_invalid;
                return status;
            }
            for (size_t j = 0; j < step.correction_count; ++j) {
                const auto &correction = step.corrections[j];
                double replay_nis = 0;
                status = as_inertial_update_position(&predicted, correction.position,
                    correction.standard_deviation, correction.maximum_nis, &replay_nis);
                if (status != AS_OK) {
                    ++fusion->stats.rejected_invalid;
                    return status;
                }
            }
            step.state = predicted;
        }
        fusion->history.swap(revised);
        fusion->state = fusion->history.back().state;
        fusion->stats.last_nis = innovation;
        fusion->stats.last_position_sequence = sequence;
        ++fusion->stats.corrected;
        return AS_OK;
    } catch (...) {
        ++fusion->stats.rejected_invalid;
        return AS_INVALID_ARGUMENT;
    }
}
}

extern "C" ASFusion *as_fusion_create(double time, ASPose3 pose,
                                      const double stds[5], ASInertialNoise noise) {
    if (!stds) return nullptr;
    auto *fusion = new(std::nothrow) ASFusion;
    if (!fusion) return nullptr;
    if (as_inertial_initialize(&fusion->state, time, pose, stds) != AS_OK) {
        delete fusion;
        return nullptr;
    }
    const double vals[] = {noise.accelerometer_std_mps2, noise.gyroscope_std_rps,
        noise.accelerometer_bias_walk_mps2, noise.gyroscope_bias_walk_rps, noise.maximum_step_s};
    for (double v : vals) if (!std::isfinite(v) || v <= 0 || v > 1000) {
        delete fusion;
        return nullptr;
    }
    fusion->noise = noise;
    fusion->stats.healthy = 1;
    try {
        HistoryStep initial;
        initial.state = fusion->state;
        fusion->history.push_back(initial);
    } catch (...) {
        delete fusion;
        return nullptr;
    }
    return fusion;
}
extern "C" void as_fusion_destroy(ASFusion *fusion) { delete fusion; }
extern "C" ASStatus as_fusion_imu(ASFusion *fusion, uint64_t sequence, double time,
                                 ASVector3 force, ASVector3 gyro) {
    if (!fusion) return AS_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> guard(fusion->lock);
    if (!fusion->stats.healthy) {
        ++fusion->stats.rejected_invalid;
        return AS_RESET_AFTER_GAP;
    }
    if (!sequence || sequence <= fusion->stats.last_imu_sequence ||
        !std::isfinite(time) || time <= fusion->state.last_time_s) {
        ++fusion->stats.rejected_time;
        return AS_INVALID_ARGUMENT;
    }
    ASInertialState next = fusion->state;
    const ASStatus status = as_inertial_predict(&next, time, force, gyro, fusion->noise);
    if (status == AS_RESET_AFTER_GAP) {
        ++fusion->stats.resets;
        fusion->stats.healthy = 0;
        return status;
    }
    if (status != AS_OK) {
        ++fusion->stats.rejected_invalid;
        return status;
    }
    try {
        HistoryStep step;
        step.state = next;
        step.force = force;
        step.gyro = gyro;
        fusion->history.push_back(step);
    } catch (...) {
        ++fusion->stats.rejected_invalid;
        return AS_INVALID_ARGUMENT;
    }
    if (fusion->history.size() > kMaximumHistory) fusion->history.pop_front();
    fusion->state = next;
    fusion->stats.last_imu_sequence = sequence;
    ++fusion->stats.predicted;
    return AS_OK;
}
extern "C" ASStatus as_fusion_position(ASFusion *fusion, uint64_t sequence, double time,
                                      ASVector3 position, double std, double gate) {
    return observe(fusion, sequence, time, position, std, gate, false);
}
extern "C" ASStatus as_fusion_position_replay(ASFusion *fusion, uint64_t sequence, double time,
                                             ASVector3 position, double std, double gate) {
    return observe(fusion, sequence, time, position, std, gate, true);
}
extern "C" int as_fusion_snapshot(const ASFusion *fusion, ASInertialState *state,
                                 ASFusionReport *report) {
    if (!fusion || !state || !report) return 0;
    std::lock_guard<std::mutex> guard(fusion->lock);
    *state = fusion->state;
    *report = fusion->stats;
    return 1;
}
