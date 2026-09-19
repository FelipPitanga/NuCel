import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "NuCel | Nuvix",
  description: "Seus celulares, em um só lugar.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="pt-BR">
      <body className="antialiased">{children}</body>
    </html>
  );
}
