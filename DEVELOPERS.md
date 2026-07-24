# Developers Notes

This repo contains code that is sensitive to the changes made to [OpenCHAMI Release](https://github.com/openchami/release)
and will need to change in response to changes made there. An effort is made
here to do the following:

- Make all changes required here that support new OpenCHAMI Release versions
configurable so that the new behavior and the old behavior is available via
configuration
- Provide the necessary configuration overlays to configure the most recent
versions of this repository can still work with previous versions of OpenCHAMI
Release.
- Provide for flexibility to patch versions of this repository used for
previous releases when issues arise.

To that end, the following is required when proposing changes to this repo:

- If the change introduces new behavior to support new OpenCHAMI Release
  behavior
  - Define new configuration parameters to disable or adjust the new behavior
  - Define values for the new configuration parameters that enable the new
    behavior.
    - Record the new behavior settings in the
      [base configuration](deploy_openchami/config/config.yaml).
    - Also record the new behavior settings in a new example configuration
      overlay file named to reflect the version of OpenCHAMI Release at
      which they take effect. For example, if your changes are there to
      support OpenCHAMI Release v0.2.0, create
      `docs/example-overlays/config-0.2.0` with the new settings in it.
  - Define values for the new configuration parameters that preserve the
    previous behavior
    - Record the values that preserve the old behavior in all earlier existing
      OpenCHAMI Release configuration overlay files as well. For example,
      if you are creating `docs/example-overlays/config-0.2.0` and there is
      a `docs/example-overlays/config-0.1.4` already there, update
      `docs/example-overlayse/config-0.1.4` with the old behavior
      configuration settings.
  - Bump the version tag for your merged PR to the next minor version, for
    example, from v0.1.x to v0.2.0)
- If the change is simply a bug fix that applies to a range of minor releases
  - Cherry pick it back as far as it make sense into patch versions of
    previous minor releases.
  - Bump the current patch number on the current minor release but do not
    create a new minor release.

By following these procedures you preserve the ability to run the latest code
to deploy older versions of OpenCHAMI Release into the future while enabling
this code to track forward as OpenCHAMI Release evolves.
