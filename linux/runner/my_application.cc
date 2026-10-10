#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void copy_file_if_exists(const gchar* src, const gchar* dest) {
  if (g_file_test(src, G_FILE_TEST_EXISTS)) {
    g_autoptr(GFile) src_file = g_file_new_for_path(src);
    g_autoptr(GFile) dest_file = g_file_new_for_path(dest);
    g_file_copy(src_file, dest_file, G_FILE_COPY_OVERWRITE, nullptr, nullptr, nullptr, nullptr);
  }
}

// Ensures .desktop file and icons exist in ~/.local/share for Wayland compositors (KDE Plasma, GNOME Shell)
static void ensure_linux_desktop_integration() {
  // If running inside Flatpak, desktop entries and icons are managed natively by the sandbox
  if (g_file_test("/.flatpak-info", G_FILE_TEST_EXISTS) || g_getenv("FLATPAK_ID") != nullptr) {
    return;
  }

  gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path == nullptr) return;

  const gchar* data_home = g_get_user_data_dir();
  if (data_home == nullptr) {
    g_free(exe_path);
    return;
  }

  g_autoptr(GFile) exe_file = g_file_new_for_path(exe_path);
  g_autoptr(GFile) exe_dir = g_file_get_parent(exe_file);
  gchar* exe_dir_path = g_file_get_path(exe_dir);

  gchar* logo_png = nullptr;
  gchar* logo_svg = nullptr;

  gchar* candidate_png = g_build_filename(exe_dir_path, "data", "flutter_assets", "assets", "images", "logo.png", nullptr);
  gchar* candidate_svg = g_build_filename(exe_dir_path, "data", "flutter_assets", "assets", "images", "logo.svg", nullptr);

  if (g_file_test(candidate_png, G_FILE_TEST_EXISTS)) {
    logo_png = candidate_png;
  } else if (g_file_test("assets/images/logo.png", G_FILE_TEST_EXISTS)) {
    g_free(candidate_png);
    logo_png = g_strdup("assets/images/logo.png");
  } else {
    g_free(candidate_png);
  }

  if (g_file_test(candidate_svg, G_FILE_TEST_EXISTS)) {
    logo_svg = candidate_svg;
  } else if (g_file_test("assets/images/logo.svg", G_FILE_TEST_EXISTS)) {
    g_free(candidate_svg);
    logo_svg = g_strdup("assets/images/logo.svg");
  } else {
    g_free(candidate_svg);
  }

  gchar* apps_dir = g_build_filename(data_home, "applications", nullptr);
  gchar* pixmaps_dir = g_build_filename(data_home, "pixmaps", nullptr);
  gchar* icons_hicolor_scalable = g_build_filename(data_home, "icons", "hicolor", "scalable", "apps", nullptr);
  gchar* icons_hicolor_256 = g_build_filename(data_home, "icons", "hicolor", "256x256", "apps", nullptr);
  gchar* icons_hicolor_root = g_build_filename(data_home, "icons", "hicolor", nullptr);

  g_mkdir_with_parents(apps_dir, 0755);
  g_mkdir_with_parents(pixmaps_dir, 0755);
  g_mkdir_with_parents(icons_hicolor_scalable, 0755);
  g_mkdir_with_parents(icons_hicolor_256, 0755);

  gchar* local_index_theme = g_build_filename(icons_hicolor_root, "index.theme", nullptr);
  if (!g_file_test(local_index_theme, G_FILE_TEST_EXISTS)) {
    if (g_file_test("/usr/share/icons/hicolor/index.theme", G_FILE_TEST_EXISTS)) {
      copy_file_if_exists("/usr/share/icons/hicolor/index.theme", local_index_theme);
    }
  }
  g_free(local_index_theme);

  if (logo_png != nullptr) {
    gchar* dest_png1 = g_build_filename(icons_hicolor_256, "com.podcastmerlin.podcast_merlin_flutter.png", nullptr);
    gchar* dest_png2 = g_build_filename(icons_hicolor_256, "podcast_merlin_flutter.png", nullptr);
    gchar* dest_pixmap1 = g_build_filename(pixmaps_dir, "com.podcastmerlin.podcast_merlin_flutter.png", nullptr);
    gchar* dest_pixmap2 = g_build_filename(pixmaps_dir, "podcast_merlin_flutter.png", nullptr);

    copy_file_if_exists(logo_png, dest_png1);
    copy_file_if_exists(logo_png, dest_png2);
    copy_file_if_exists(logo_png, dest_pixmap1);
    copy_file_if_exists(logo_png, dest_pixmap2);

    g_free(dest_png1);
    g_free(dest_png2);
    g_free(dest_pixmap1);
    g_free(dest_pixmap2);
    g_free(logo_png);
  }

  if (logo_svg != nullptr) {
    gchar* dest_svg1 = g_build_filename(icons_hicolor_scalable, "com.podcastmerlin.podcast_merlin_flutter.svg", nullptr);
    gchar* dest_svg2 = g_build_filename(icons_hicolor_scalable, "podcast_merlin_flutter.svg", nullptr);
    gchar* dest_pixmap1 = g_build_filename(pixmaps_dir, "com.podcastmerlin.podcast_merlin_flutter.svg", nullptr);
    gchar* dest_pixmap2 = g_build_filename(pixmaps_dir, "podcast_merlin_flutter.svg", nullptr);

    copy_file_if_exists(logo_svg, dest_svg1);
    copy_file_if_exists(logo_svg, dest_svg2);
    copy_file_if_exists(logo_svg, dest_pixmap1);
    copy_file_if_exists(logo_svg, dest_pixmap2);

    g_free(dest_svg1);
    g_free(dest_svg2);
    g_free(dest_pixmap1);
    g_free(dest_pixmap2);
    g_free(logo_svg);
  }

  gchar* desktop_path1 = g_build_filename(apps_dir, "com.podcastmerlin.podcast_merlin_flutter.desktop", nullptr);
  gchar* desktop_path2 = g_build_filename(apps_dir, "podcast_merlin_flutter.desktop", nullptr);

  gchar* desktop_content = g_strdup_printf(
      "[Desktop Entry]\n"
      "Version=1.0\n"
      "Type=Application\n"
      "Name=Podcast Merlin\n"
      "GenericName=Podcast Client\n"
      "Comment=Nextcloud & gPodder Podcast Client\n"
      "Exec=%s %%U\n"
      "Icon=com.podcastmerlin.podcast_merlin_flutter\n"
      "Terminal=false\n"
      "Categories=AudioVideo;Audio;Player;\n"
      "StartupWMClass=%s\n",
      exe_path, APPLICATION_ID);

  g_file_set_contents(desktop_path1, desktop_content, -1, nullptr);

  gchar* desktop_content2 = g_strdup_printf(
      "[Desktop Entry]\n"
      "Version=1.0\n"
      "Type=Application\n"
      "Name=Podcast Merlin\n"
      "GenericName=Podcast Client\n"
      "Comment=Nextcloud & gPodder Podcast Client\n"
      "Exec=%s %%U\n"
      "Icon=podcast_merlin_flutter\n"
      "Terminal=false\n"
      "Categories=AudioVideo;Audio;Player;\n"
      "StartupWMClass=podcast_merlin_flutter\n",
      exe_path);

  g_file_set_contents(desktop_path2, desktop_content2, -1, nullptr);

  g_spawn_command_line_async(
      "sh -c 'update-desktop-database ~/.local/share/applications 2>/dev/null; "
      "kbuildsycoca6 --noincremental 2>/dev/null; "
      "gtk-update-icon-cache -f ~/.local/share/icons/hicolor 2>/dev/null'",
      nullptr);

  g_free(desktop_content);
  g_free(desktop_content2);
  g_free(desktop_path1);
  g_free(desktop_path2);
  g_free(apps_dir);
  g_free(pixmaps_dir);
  g_free(icons_hicolor_scalable);
  g_free(icons_hicolor_256);
  g_free(icons_hicolor_root);
  g_free(exe_dir_path);
  g_free(exe_path);
}

// Helper to set window icon using multiple standard sizes for Linux desktop environments
static void set_window_icon(GtkWindow* window) {
  // Ensure Wayland and desktop environment have registered icons and .desktop entries
  ensure_linux_desktop_integration();

  // Set default and window icon names for Wayland / XDG shell integration
  gtk_window_set_default_icon_name(APPLICATION_ID);
  gtk_window_set_icon_name(window, APPLICATION_ID);

  // Append local assets directory to GtkIconTheme search path
  gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autoptr(GFile) exe_file = g_file_new_for_path(exe_path);
    g_autoptr(GFile) exe_dir = g_file_get_parent(exe_file);
    gchar* exe_dir_path = g_file_get_path(exe_dir);
    gchar* assets_images_dir = g_build_filename(exe_dir_path, "data", "flutter_assets", "assets", "images", nullptr);
    if (g_file_test(assets_images_dir, G_FILE_TEST_IS_DIR)) {
      gtk_icon_theme_append_search_path(gtk_icon_theme_get_default(), assets_images_dir);
    }
    g_free(assets_images_dir);
    g_free(exe_dir_path);
    g_free(exe_path);
  }

  gchar* icon_path = nullptr;

  if (g_file_test("assets/images/logo.png", G_FILE_TEST_EXISTS)) {
    icon_path = g_strdup("assets/images/logo.png");
  } else {
    gchar* exe_path2 = g_file_read_link("/proc/self/exe", nullptr);
    if (exe_path2 != nullptr) {
      g_autoptr(GFile) exe_file = g_file_new_for_path(exe_path2);
      g_autoptr(GFile) exe_dir = g_file_get_parent(exe_file);
      gchar* exe_dir_path = g_file_get_path(exe_dir);
      icon_path = g_build_filename(exe_dir_path, "data", "flutter_assets", "assets", "images", "logo.png", nullptr);
      g_free(exe_path2);
      g_free(exe_dir_path);
    }
  }

  if (icon_path != nullptr) {
    if (g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
      const int sizes[] = {16, 32, 48, 64, 128, 256};
      GList* icon_list = nullptr;
      for (size_t i = 0; i < sizeof(sizes) / sizeof(sizes[0]); ++i) {
        g_autoptr(GError) error = nullptr;
        GdkPixbuf* pixbuf = gdk_pixbuf_new_from_file_at_scale(
            icon_path, sizes[i], sizes[i], TRUE, &error);
        if (pixbuf != nullptr) {
          icon_list = g_list_append(icon_list, pixbuf);
        }
      }
      if (icon_list != nullptr) {
        gtk_window_set_icon_list(window, icon_list);
        gtk_window_set_default_icon_list(icon_list);
        g_list_free_full(icon_list, g_object_unref);
      }
    }
    g_free(icon_path);
  }
}

// Detect whether to use a GNOME-style client-side GtkHeaderBar or traditional
// window manager title bar (as preferred by KDE Plasma, XFCE, etc.).
static gboolean should_use_header_bar(GtkWindow* window) {
  const gchar* current_desktop = g_getenv("XDG_CURRENT_DESKTOP");
  if (current_desktop != nullptr) {
    // Non-GNOME desktop environments prefer server-side window manager decorations
    if (g_strrstr(current_desktop, "KDE") != nullptr ||
        g_strrstr(current_desktop, "plasma") != nullptr ||
        g_strrstr(current_desktop, "XFCE") != nullptr ||
        g_strrstr(current_desktop, "MATE") != nullptr ||
        g_strrstr(current_desktop, "LXQt") != nullptr ||
        g_strrstr(current_desktop, "Cinnamon") != nullptr) {
      return FALSE;
    }
    // GNOME Shell uses and expects CSD header bars
    if (g_strrstr(current_desktop, "GNOME") != nullptr) {
      return TRUE;
    }
  }

#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (wm_name != nullptr && g_strcmp0(wm_name, "GNOME Shell") != 0) {
      return FALSE;
    }
  }
#endif

  // On Wayland (Sway, Hyprland, etc.) or GNOME, assume header bar will work
  return TRUE;
}

static guint portal_setting_sub_id = 0;
static GDBusConnection* portal_dbus_conn = nullptr;

// Callback for XDG portal SettingChanged signal
static void on_portal_setting_changed(GDBusConnection* connection,
                                      const gchar* sender_name,
                                      const gchar* object_path,
                                      const gchar* interface_name,
                                      const gchar* signal_name,
                                      GVariant* parameters,
                                      gpointer user_data) {
  if (parameters == nullptr || !g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ssv)"))) {
    return;
  }

  const gchar* namespace_str = nullptr;
  const gchar* key_str = nullptr;
  g_autoptr(GVariant) value = nullptr;

  g_variant_get(parameters, "(&s&sv)", &namespace_str, &key_str, &value);
  if (namespace_str != nullptr && g_strcmp0(namespace_str, "org.freedesktop.appearance") == 0 &&
      key_str != nullptr && g_strcmp0(key_str, "color-scheme") == 0 && value != nullptr) {
    guint32 scheme = 0;
    if (g_variant_is_of_type(value, G_VARIANT_TYPE_VARIANT)) {
      g_autoptr(GVariant) inner = g_variant_get_variant(value);
      if (g_variant_is_of_type(inner, G_VARIANT_TYPE_UINT32)) {
        scheme = g_variant_get_uint32(inner);
      }
    } else if (g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32)) {
      scheme = g_variant_get_uint32(value);
    }

    // scheme: 0 = no preference (preserve system default), 1 = prefer dark, 2 = prefer light
    if (scheme == 1 || scheme == 2) {
      GtkSettings* settings = gtk_settings_get_default();
      if (settings != nullptr) {
        gboolean prefer_dark = (scheme == 1);
        g_object_set(settings, "gtk-application-prefer-dark-theme", prefer_dark, nullptr);
      }
    }
  }
}

// Synchronize GTK theme preference (dark/light) with the desktop environment (KDE, GNOME, etc.)
static void sync_gtk_theme_mode() {
  GtkSettings* settings = gtk_settings_get_default();
  if (settings == nullptr) return;

  gboolean dark_detected = FALSE;
  gboolean setting_determined = FALSE;

  // 1. Query XDG Desktop Portal for appearance color-scheme
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) connection = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (connection != nullptr) {
    g_autoptr(GVariant) result = g_dbus_connection_call_sync(
        connection,
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.Settings",
        "Read",
        g_variant_new("(ss)", "org.freedesktop.appearance", "color-scheme"),
        G_VARIANT_TYPE("(v)"),
        G_DBUS_CALL_FLAGS_NONE,
        150, // Short timeout (150ms) to prevent freezing main thread on cold launch
        nullptr,
        nullptr);

    if (result != nullptr) {
      g_autoptr(GVariant) tuple_val = nullptr;
      g_variant_get(result, "(v)", &tuple_val);
      if (tuple_val != nullptr) {
        g_autoptr(GVariant) inner_val = g_variant_get_variant(tuple_val);
        if (inner_val != nullptr) {
          guint32 scheme = 0;
          if (g_variant_is_of_type(inner_val, G_VARIANT_TYPE_VARIANT)) {
            g_autoptr(GVariant) u_val = g_variant_get_variant(inner_val);
            if (g_variant_is_of_type(u_val, G_VARIANT_TYPE_UINT32)) {
              scheme = g_variant_get_uint32(u_val);
            }
          } else if (g_variant_is_of_type(inner_val, G_VARIANT_TYPE_UINT32)) {
            scheme = g_variant_get_uint32(inner_val);
          }

          if (scheme == 1) { // Prefer dark
            dark_detected = TRUE;
            setting_determined = TRUE;
          } else if (scheme == 2) { // Prefer light
            dark_detected = FALSE;
            setting_determined = TRUE;
          }
        }
      }
    }

    // Subscribe to portal SettingChanged signal for live theme toggling
    if (portal_setting_sub_id == 0) {
      portal_dbus_conn = G_DBUS_CONNECTION(g_object_ref(connection));
      portal_setting_sub_id = g_dbus_connection_signal_subscribe(
          connection,
          "org.freedesktop.portal.Desktop",
          "org.freedesktop.portal.Settings",
          "SettingChanged",
          "/org/freedesktop/portal/desktop",
          nullptr,
          G_DBUS_SIGNAL_FLAGS_NONE,
          on_portal_setting_changed,
          nullptr,
          nullptr);
    }
  }

  // 2. If not determined by portal, check GTK 3 settings.ini and KDE kdeglobals
  if (!setting_determined) {
    const gchar* config_dir = g_get_user_config_dir();
    if (config_dir != nullptr) {
      gchar* gtk_ini = g_build_filename(config_dir, "gtk-3.0", "settings.ini", nullptr);
      if (g_file_test(gtk_ini, G_FILE_TEST_EXISTS)) {
        g_autoptr(GKeyFile) kf = g_key_file_new();
        if (g_key_file_load_from_file(kf, gtk_ini, G_KEY_FILE_NONE, nullptr)) {
          if (g_key_file_has_key(kf, "Settings", "gtk-application-prefer-dark-theme", nullptr)) {
            dark_detected = g_key_file_get_boolean(kf, "Settings", "gtk-application-prefer-dark-theme", nullptr);
            setting_determined = TRUE;
          }
        }
      }
      g_free(gtk_ini);

      if (!setting_determined) {
        gchar* kde_ini = g_build_filename(config_dir, "kdeglobals", nullptr);
        if (g_file_test(kde_ini, G_FILE_TEST_EXISTS)) {
          g_autoptr(GKeyFile) kf = g_key_file_new();
          if (g_key_file_load_from_file(kf, kde_ini, G_KEY_FILE_NONE, nullptr)) {
            gchar* color_scheme = g_key_file_get_string(kf, "General", "ColorScheme", nullptr);
            if (color_scheme != nullptr) {
              dark_detected = (g_strrstr(color_scheme, "Dark") != nullptr || g_strrstr(color_scheme, "Black") != nullptr);
              setting_determined = TRUE;
              g_free(color_scheme);
            }
          }
        }
        g_free(kde_ini);
      }
    }
  }

  if (setting_determined) {
    g_object_set(settings, "gtk-application-prefer-dark-theme", dark_detected, nullptr);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a GNOME header bar only when running in GNOME.
  // For KDE Plasma and other desktop environments, let the window manager
  // draw native window decorations (SSD) matching the system theme and button layout.
  gboolean use_header_bar = should_use_header_bar(window);
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Podcast Merlin");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Podcast Merlin");
  }

  // Set Linux taskbar and window icon
  set_window_icon(window);

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  g_set_prgname(APPLICATION_ID);
  g_set_application_name("Podcast Merlin");

  sync_gtk_theme_mode();

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  if (portal_dbus_conn != nullptr && portal_setting_sub_id != 0) {
    g_dbus_connection_signal_unsubscribe(portal_dbus_conn, portal_setting_sub_id);
    portal_setting_sub_id = 0;
    g_clear_object(&portal_dbus_conn);
  }

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
