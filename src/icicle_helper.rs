use crate::F;
use icicle_core::{
    curve::{Affine, Curve, Projective},
    msm::{msm, MSMConfig, MSM},
    ntt::{ntt_inplace, NTTConfig, NTTDir, NTT},
    traits::FieldImpl,
};
use icicle_runtime::{
    memory::{DeviceSlice, DeviceVec},
    stream::IcicleStream,
};

pub fn ntt_helper(vec: &mut DeviceSlice<F>, inverse: bool, stream: &IcicleStream)
where
    <F as FieldImpl>::Config: NTT<F, F>,
{
    let dir = if inverse {
        NTTDir::kInverse
    } else {
        NTTDir::kForward
    };

    let mut cfg1 = NTTConfig::<F>::default();
    cfg1.is_async = true;
    cfg1.batch_size = 3;
    cfg1.stream_handle = stream.into();

    ntt_inplace(vec, dir, &cfg1).unwrap();
}

pub fn msm_helper<C: Curve + MSM<C>>(
    scalars: &DeviceSlice<C::ScalarField>,
    points: &DeviceSlice<Affine<C>>,
    stream: &IcicleStream,
) -> DeviceVec<Projective<C>> {
    let mut msm_result = DeviceVec::<Projective<C>>::device_malloc_async(1, stream).unwrap();
    let mut msm_config = MSMConfig::default();
    msm_config.stream_handle = stream.into();
    msm_config.is_async = true;

    msm(scalars, points, &msm_config, &mut msm_result[..]).unwrap();

    msm_result
}
