describe("Profile parsing", function()
    _G._TEST = true
    package.path = 'scripts/?;' .. package.path
    local chwd = require("chwd")

    describe("Valid cases", function()
        local profiles = chwd.parse_profiles("tests/profiles/graphic_drivers-profiles-test.toml")
        local name = "nvidia-dkms"

        it("Profiles are available", function()
            assert.are_not.same(profiles, {})
        end)

        local profile = profiles[name]
        it("Search for profile", function()
            assert.truthy(profile)
        end)

        describe("Attributes", function()
            local packages, hooks = chwd.get_profile(profiles, name)
            it("Packages", function()
                assert.are.equals(packages,
                    "nvidia-utils egl-wayland nvidia-settings opencl-nvidia lib32-opencl-nvidia lib32-nvidia-utils libva-nvidia-driver vulkan-icd-loader lib32-vulkan-icd-loader")
            end)
            it("Hooks", function()
                assert.truthy(hooks)
            end)
            it("Post remove hook", function()
                assert.are.equals(hooks['post_remove'], [[
    rm -f /etc/mkinitcpio.conf.d/10-chwd.conf
    mkinitcpio -P
]])
            end)
            it("Post install hook", function()
                assert.are.equals(hooks['post_install'], [[
    cat <<EOF >/etc/mkinitcpio.conf.d/10-chwd.conf
# This file is automatically generated by chwd. PLEASE DO NOT EDIT IT.
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
    mkinitcpio -P
]])
            end)
            it("Conditional packages hook", function()
                assert.are.equals(hooks['conditional_packages'], [[
    kernels="$(pacman -Qqs "^linux-cachyos")"
    modules=""

    for kernel in $kernels; do
        case "$kernel" in
            *-headers|*-zfs);;
            *-nvidia) modules+=" ${kernel}";;
            *) modules+=" ${kernel}-nvidia";;
        esac
    done

    # Fallback if there are no kernels with pre-built modules
    [ -z "$modules" ] && modules="nvidia-dkms"

    echo "$modules"
]])
            end)
        end)

        local child_name = "nvidia-dkms.40xxcards"
        local child_profile = profiles[child_name]
        it("Search for child profile", function()
            assert.truthy(child_profile)
        end)

        describe("Inheritance", function()
            local packages, hooks = chwd.get_profile(profiles, child_name)
            it("Inherit parent packages", function()
                assert.are.equals(packages,
                    "nvidia-utils egl-wayland nvidia-settings opencl-nvidia lib32-opencl-nvidia lib32-nvidia-utils libva-nvidia-driver vulkan-icd-loader lib32-vulkan-icd-loader")
            end)
            it("Inherit some parent hook", function()
                assert.are.equals(hooks['post_remove'], [[
    rm -f /etc/mkinitcpio.conf.d/10-chwd.conf
    mkinitcpio -P
]])
            end)
        end)

        describe("Packages inspection", function()
            local lfs = require("lfs")

            local function search(path, t)
                for file in lfs.dir(path) do
                    if file ~= "." and file ~= ".." then
                        local f = path .. '/' .. file
                        local attr = lfs.attributes(f)
                        assert(type(attr) == "table")
                        if attr.mode == "directory" then
                            search(f, t)
                        else
                            if f:match('.toml$') then
                                t[#t + 1] = f
                            end
                        end
                    end
                end
            end

            local available_profiles = {}
            search("./profiles", available_profiles)

            it("Packages are available in repo", function()
                for _, file in ipairs(available_profiles) do
                    local profiles = chwd.parse_profiles(file)
                    for pname, _ in pairs(profiles) do
                        local packages = chwd.get_profile(profiles, pname)
                        print(string.format("Checking profile %s for available packages: %s...", pname, packages))
                        local _, _, exitcode = os.execute("pacman -Sp " .. packages .. " 1>/dev/null")
                        assert.True(exitcode == 0)
                    end
                end
            end)
        end)
    end)

    describe("Invalid cases", function()
        it("Profiles are not available", function()
            assert.are.same(chwd.parse_profiles("/dev/null"), {})
        end)

        local profiles = chwd.parse_profiles("tests/profiles/graphic_drivers-invalid-profiles-test.toml")
        it("Non-existing profile", function()
            assert.is.falsy(profiles['unknown'])
        end)
        it("Unspecified packages", function()
            assert.is.falsy(profiles['invalid'].packages)
        end)
    end)
end)
