import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json({ message: "Method not allowed" }, { status: 405 });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return Response.json({ message: "Missing user token" }, { status: 401 });
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !anonKey || !serviceRoleKey) {
    return Response.json({ message: "Server configuration is incomplete" }, { status: 500 });
  }

  const userClient = createClient(supabaseURL, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return Response.json({ message: "Invalid or expired user token" }, { status: 401 });
  }

  const admin = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { error: deletionError } = await admin.auth.admin.deleteUser(userData.user.id);
  if (deletionError) {
    console.error("delete-account", deletionError);
    return Response.json({ message: "Account deletion failed" }, { status: 500 });
  }

  return Response.json({});
});
