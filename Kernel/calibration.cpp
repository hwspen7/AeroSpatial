#include "include/aerospatial_calibration.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace {
bool valid_camera(const ASCameraIntrinsics &c) {
    return c.width && c.height && c.width <= 16384 && c.height <= 16384 &&
        std::isfinite(c.fx) && std::isfinite(c.fy) &&
        std::isfinite(c.cx) && std::isfinite(c.cy) && c.fx > 0 && c.fy > 0;
}
bool valid_lens(const ASLensDistortion &l) {
    return std::isfinite(l.k1) && std::isfinite(l.k2) && std::isfinite(l.k3) &&
        std::isfinite(l.p1) && std::isfinite(l.p2) &&
        std::abs(l.k1) <= 2 && std::abs(l.k2) <= 2 && std::abs(l.k3) <= 2 &&
        std::abs(l.p1) <= 1 && std::abs(l.p2) <= 1;
}
struct Model { double x, y, j11, j12, j21, j22; };
Model distort(double x, double y, ASLensDistortion l) {
    const double r2=x*x+y*y, r4=r2*r2, r6=r4*r2;
    const double radial=1+l.k1*r2+l.k2*r4+l.k3*r6;
    const double derivative=2*(l.k1+2*l.k2*r2+3*l.k3*r4);
    const double xy=x*y;
    return {x*radial+2*l.p1*xy+l.p2*(r2+2*x*x),
            y*radial+l.p1*(r2+2*y*y)+2*l.p2*xy,
            radial+x*x*derivative+2*l.p1*y+6*l.p2*x,
            x*y*derivative+2*l.p1*x+2*l.p2*y,
            x*y*derivative+2*l.p1*x+2*l.p2*y,
            radial+y*y*derivative+6*l.p1*y+2*l.p2*x};
}
template <class T> double median(std::vector<T> &values) {
    const size_t mid=values.size()/2;
    std::nth_element(values.begin(),values.begin()+mid,values.end());
    const double upper=values[mid];
    if (values.size()%2) return upper;
    std::nth_element(values.begin(),values.begin()+mid-1,values.begin()+mid);
    return (upper+values[mid-1])*0.5;
}
}

extern "C" ASStatus as_camera_project_distorted(ASCameraIntrinsics c, ASLensDistortion l,
                                                   ASVector3 ray, double *px, double *py) {
    if (!px || !py || !valid_camera(c) || !valid_lens(l) ||
        !std::isfinite(ray.x) || !std::isfinite(ray.y) || !std::isfinite(ray.z) ||
        ray.z <= 1e-10) return AS_INVALID_ARGUMENT;
    const auto m=distort(ray.x/ray.z,ray.y/ray.z,l);
    const double x=c.fx*m.x+c.cx, y=c.fy*m.y+c.cy;
    if (!std::isfinite(x) || !std::isfinite(y) || x < 0 || y < 0 || x >= c.width || y >= c.height)
        return AS_INVALID_ARGUMENT;
    *px=x;*py=y;
    return AS_OK;
}
extern "C" ASStatus as_camera_unproject_distorted(ASCameraIntrinsics c, ASLensDistortion l,
                                                     double px, double py, ASVector3 *ray) {
    if (!ray || !valid_camera(c) || !valid_lens(l) || !std::isfinite(px) || !std::isfinite(py) ||
        px<0 || py<0 || px>=c.width || py>=c.height) return AS_INVALID_ARGUMENT;
    const double xd=(px-c.cx)/c.fx, yd=(py-c.cy)/c.fy;
    double x=xd,y=yd;
    bool converged=false;
    for(int i=0;i<16;i++) {
        const auto m=distort(x,y,l);
        const double ex=m.x-xd, ey=m.y-yd;
        if (std::max(std::abs(ex),std::abs(ey)) < 1e-11) {converged=true;break;}
        const double determinant=m.j11*m.j22-m.j12*m.j21;
        if(!std::isfinite(determinant) || std::abs(determinant)<1e-12) break;
        const double dx=(m.j22*ex-m.j12*ey)/determinant;
        const double dy=(-m.j21*ex+m.j11*ey)/determinant;
        if(!std::isfinite(dx) || !std::isfinite(dy) || std::max(std::abs(dx),std::abs(dy))>2) break;
        x-=dx;y-=dy;
    }
    if (!converged) return AS_OUTLIER_REJECTED;
    const double norm=std::hypot(std::hypot(x,y),1.0);
    if (!std::isfinite(norm) || norm<=0) return AS_INVALID_ARGUMENT;
    *ray={x/norm,y/norm,1/norm};
    return AS_OK;
}

extern "C" ASStatus as_clock_fit_robust(const ASClockSample *samples, size_t count,
                                           double max_ppm, double gate, ASClockFit *fit) {
    if (!samples || !fit || count<4 || count>128 || !std::isfinite(max_ppm) ||
        !std::isfinite(gate) || max_ppm<1 || max_ppm>10000 || gate<=0 || gate>1) return AS_INVALID_ARGUMENT;
    for(size_t i=0;i<count;i++) {
        if(!std::isfinite(samples[i].source_seconds) || !std::isfinite(samples[i].host_seconds) ||
           samples[i].source_seconds<0 || samples[i].host_seconds<0 ||
           (i>0 && (samples[i].source_seconds<=samples[i-1].source_seconds ||
                    samples[i].host_seconds<=samples[i-1].host_seconds))) return AS_INVALID_ARGUMENT;
    }
    if(samples[count-1].source_seconds - samples[0].source_seconds < 0.01) return AS_INVALID_ARGUMENT;
    std::vector<double> slopes;
    slopes.reserve(count*(count-1)/2);
    for(size_t i=0;i<count;i++) for(size_t j=i+1;j<count;j++) {
        const double dx=samples[j].source_seconds-samples[i].source_seconds;
        if(dx>1e-6) {
            const double slope=(samples[j].host_seconds-samples[i].host_seconds)/dx;
            if(std::isfinite(slope)) slopes.push_back(slope);
        }
    }
    if(slopes.empty()) return AS_INVALID_ARGUMENT;
    double slope=median(slopes);
    if(std::abs(slope-1)>max_ppm*1e-6) return AS_OUTLIER_REJECTED;
    std::vector<double> intercepts;
    intercepts.reserve(count);
    const double anchor=samples[0].source_seconds;
    for(size_t i=0;i<count;i++) intercepts.push_back(samples[i].host_seconds-slope*(samples[i].source_seconds-anchor));
    const double centered_intercept=median(intercepts);
    double n=0,mx=0,my=0,sxx=0,sxy=0;
    for(size_t i=0;i<count;i++) {
        const double x=samples[i].source_seconds-anchor;
        const double residual=samples[i].host_seconds-(centered_intercept+slope*x);
        if(std::abs(residual)>gate) continue;
        n++;const double dx=x-mx;mx+=dx/n;
        const double dy=samples[i].host_seconds-my;my+=dy/n;
        sxx+=dx*(x-mx);sxy+=dx*(samples[i].host_seconds-my);
    }
    if(n<4 || sxx<=1e-15) return AS_OUTLIER_REJECTED;
    slope=sxy/sxx;
    if(!std::isfinite(slope) || std::abs(slope-1)>max_ppm*1e-6) return AS_OUTLIER_REJECTED;
    const double offset=my-slope*mx-slope*anchor;
    double rss=0;
    for(size_t i=0;i<count;i++) {
        const double residual=samples[i].host_seconds-(slope*samples[i].source_seconds+offset);
        if(std::abs(residual)<=gate) rss+=residual*residual;
    }
    const double rms=std::sqrt(rss/n);
    if(!std::isfinite(offset) || !std::isfinite(rms)) return AS_INVALID_ARGUMENT;
    const ASClockFit result{slope,offset,rms,samples[0].source_seconds,
                            samples[count-1].source_seconds,max_ppm,
                            static_cast<unsigned int>(n),static_cast<unsigned int>(count-n)};
    *fit=result;
    return AS_OK;
}
extern "C" ASStatus as_clock_translate(const ASClockFit *fit,double source,double horizon,
                                          double *host,double *uncertainty) {
    if(!fit || !host || !uncertainty || !std::isfinite(source) || source<0 ||
       !std::isfinite(horizon) || horizon<0 || horizon>3600 || fit->inliers<4 ||
       !std::isfinite(fit->scale) || !std::isfinite(fit->offset_seconds) ||
       !std::isfinite(fit->residual_rms_seconds) || fit->residual_rms_seconds<0 ||
       !std::isfinite(fit->drift_uncertainty_ppm) || fit->drift_uncertainty_ppm<0 ||
       !std::isfinite(fit->first_source_seconds) || !std::isfinite(fit->last_source_seconds) ||
       fit->last_source_seconds<fit->first_source_seconds) return AS_INVALID_ARGUMENT;
    const double extrapolation=source<fit->first_source_seconds ? fit->first_source_seconds-source :
        source>fit->last_source_seconds ? source-fit->last_source_seconds : 0;
    if(extrapolation>horizon) return AS_OUTLIER_REJECTED;
    const double translated=fit->scale*source+fit->offset_seconds;
    const double error=fit->residual_rms_seconds+extrapolation*fit->drift_uncertainty_ppm*1e-6;
    if(!std::isfinite(translated) || !std::isfinite(error)) return AS_INVALID_ARGUMENT;
    *host=translated;*uncertainty=error;
    return AS_OK;
}
