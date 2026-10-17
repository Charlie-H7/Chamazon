"use client"
export default function LoginPage() {
  return (
    // <div className="flex min-h-full w-[calc(100vh-8rem)] w-max-1200px flex-col justify-center px-6 py-12 my-6 mx-auto lg:px-8 border-1 border-rounded">
    <div className="flex min-h-full lg:max-w-[400px] w-100% margin-inline flex-col justify-center px-6 py-6 my-6 mx-auto lg:px-8 lg:border-1 rounded-lg">
      <div className="">
        <div>Sign in!</div>
        <form action="" className="flex flex-col">
          <label htmlFor="">Enter an email</label>
          <input type="text" className="bg-white text-black"/>
          <button>Submit</button>
          {/* MAKE THE UNDERLINE HERE */}
        </form>
          <div className="border-t-1">
            <span>By continuing you agree to entrust me with your data (a wise choice)</span>
          </div>
      </div>
    </div>
  );
}