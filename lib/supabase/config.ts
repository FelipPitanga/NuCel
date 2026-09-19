const required = (name: string) => {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`CONFIG:${name}`);
  return value.replace(/\/$/, '');
};

export function supabaseConfig() {
  return {
    url: required('SUPABASE_URL'),
    publishableKey: required('SUPABASE_PUBLISHABLE_KEY'),
    secretKey: required('SUPABASE_SECRET_KEY'),
    ownerEmail: required('NUCEL_OWNER_EMAIL').toLowerCase(),
  };
}
