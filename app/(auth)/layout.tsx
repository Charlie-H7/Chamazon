import Footer from "@/components/wrapper/footer";
import Header from "@/components/wrapper/header";

export default async function ProtectedLayout({ children }: {
  children: React.ReactNode;
}) {
  return (
    <div>
      <Header />
      <main className="justify-center">
        {children}
      </main>
      <Footer />
    </div>
  );
}
